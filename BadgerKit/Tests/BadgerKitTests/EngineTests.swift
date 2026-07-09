//
//  EngineTests.swift
//  BadgerKitTests — engine + notification-channel integration (§8/§9/§10/§18).
//
//  Uses an in-memory container + a FakeChannel (no UserNotifications), injected time
//  via a captured clock. Asserts the channel received the right schedule/cancel calls
//  (incl. the bounded repeat batch), the event log persisted in order, and the Badger
//  caches were updated. Real on-device notification delivery is an M8/device check.
//

import Testing
import Foundation
import SwiftData
@testable import BadgerKit

/// Records what the engine asked a channel to do, without touching the system.
actor FakeChannel: AlertChannel {
    nonisolated let id: String
    nonisolated let capabilities: ChannelCapabilities

    struct Scheduled: Equatable {
        let fireDate: Date
        let badgerID: UUID
        let slot: ScheduleSlot
        let prominence: Prominence
    }
    private(set) var scheduled: [Scheduled] = []
    private(set) var cancelledAll: [UUID] = []

    init(id: String = "notification") {
        self.id = id
        self.capabilities = ChannelCapabilities(
            prominences: [.passive, .active, .timeSensitive],
            deliversInBackground: true, observableAtFire: false,
            needsWidget: false, supportsArbitraryRecurrence: false)
    }

    func schedule(_ action: ChannelAction, at fireDate: Date, recurrence: ChannelRecurrence?,
                  badgerID: UUID, slot: ScheduleSlot) async throws -> ScheduledRef {
        scheduled.append(Scheduled(fireDate: fireDate, badgerID: badgerID,
                                   slot: slot, prominence: action.prominence))
        return ScheduledRef(channelID: id, identifier: "\(id)|\(badgerID)|\(slot)", slot: slot)
    }
    func cancel(_ ref: ScheduledRef) async { scheduled.removeAll { $0.slot == ref.slot } }
    func cancelAll(forBadgerID badgerID: UUID) async {
        cancelledAll.append(badgerID)
        scheduled.removeAll { $0.badgerID == badgerID }
    }

    var slots: [ScheduleSlot] { scheduled.map(\.slot) }
    var rungSlots: [Int] {
        scheduled.compactMap { if case .rung(let k) = $0.slot { return k } else { return nil } }.sorted()
    }
    var repeatCount: Int {
        scheduled.filter { if case .repeatTail = $0.slot { return true } else { return false } }.count
    }
}

/// A fake shaped like the alarmkit channel: returns UUID-string identifiers (so the
/// engine stores them in armedAlarms) and declares itself observable.
actor FakeAlarmChannel: AlertChannel {
    nonisolated let id = "alarmkit"
    nonisolated let capabilities = ChannelCapabilities(
        prominences: [.breakthrough], deliversInBackground: true, observableAtFire: true,
        needsWidget: true, supportsArbitraryRecurrence: false)

    private(set) var scheduled: [ScheduleSlot] = []
    func schedule(_ action: ChannelAction, at fireDate: Date, recurrence: ChannelRecurrence?,
                  badgerID: UUID, slot: ScheduleSlot) async throws -> ScheduledRef {
        scheduled.append(slot)
        return ScheduledRef(channelID: id, identifier: UUID().uuidString, slot: slot)
    }
    func cancel(_ ref: ScheduledRef) async {}
    func cancelAll(forBadgerID badgerID: UUID) async {}
}

@Suite("BadgerKit engine + notification channel (Phase 5 §8/§9/§10)")
@MainActor
struct EngineTests {

    private let T0 = Date(timeIntervalSinceReferenceDate: 0)
    private func at(_ s: TimeInterval) -> Date { T0.addingTimeInterval(s) }

    // rung0 @ +0, rung1 @ +60, rung2 @ +180 (last). Repeat interval = 120.
    private var ladder: [RungSpec] {
        [
            RungSpec(index: 0, delay: 0,   actions: [ChannelAction(channelID: "notification", prominence: .active)]),
            RungSpec(index: 1, delay: 60,  actions: [ChannelAction(channelID: "notification", prominence: .timeSensitive)]),
            RungSpec(index: 2, delay: 180, actions: [ChannelAction(channelID: "notification", prominence: .timeSensitive)]),
        ]
    }

    private func fetchBadger(_ id: UUID, _ c: ModelContainer) -> Badger? {
        var fd = FetchDescriptor<Badger>(predicate: #Predicate { $0.id == id }); fd.fetchLimit = 1
        return (try? c.mainContext.fetch(fd))?.first
    }
    private func eventKinds(_ id: UUID, _ c: ModelContainer) -> [EventKind] {
        let fd = FetchDescriptor<EventRecord>(predicate: #Predicate { $0.badgerID == id },
                                              sortBy: [SortDescriptor(\.sequence)])
        return ((try? c.mainContext.fetch(fd)) ?? []).map(\.kind)
    }

    // MARK: - Tests

    @Test("create arms rungs 0…last + a bounded repeat batch, logs created/armed, pends")
    func createArms() async throws {
        let clock = at(0)
        let c = try makeModelContainer(inMemory: true)
        let fake = FakeChannel()
        let engine = BadgerEngine(container: c, registry: AlertChannelRegistry([fake]),
                                  repeatBatchSize: 4, now: { clock })
        let id = await engine.create(title: "Take meds", startAt: at(0),
                                     rungs: ladder, maxSnoozeCount: 1)

        #expect(await fake.rungSlots == [0, 1, 2])
        #expect(await fake.repeatCount == 4)

        let b = try #require(fetchBadger(id, c))
        #expect(b.state == .pending)
        #expect(b.armedAlarms.isEmpty)               // notification rungs aren't persisted (prefix-scan teardown)
        #expect(eventKinds(id, c) == [.created, .armed])
    }

    @Test("Done cancels everything, logs done, stamps resolvedAt")
    func doneResolves() async throws {
        var clock = at(0)
        let c = try makeModelContainer(inMemory: true)
        let fake = FakeChannel()
        let engine = BadgerEngine(container: c, registry: AlertChannelRegistry([fake]), now: { clock })
        let id = await engine.create(title: "x", startAt: at(0), rungs: ladder, maxSnoozeCount: 1)
        clock = at(30)
        await engine.markDone(id)

        #expect(await fake.cancelledAll.contains(id))
        let b = try #require(fetchBadger(id, c))
        #expect(b.state == .done)
        #expect(b.resolvedAt == at(30))
        #expect(eventKinds(id, c).contains(.userMarkedDone))
    }

    @Test("a notification Done action resolves the Badger through the engine")
    func notificationDoneAction() async throws {
        var clock = at(0)
        let c = try makeModelContainer(inMemory: true)
        let engine = BadgerEngine(container: c, registry: AlertChannelRegistry([FakeChannel()]), now: { clock })
        let id = await engine.create(title: "x", startAt: at(0), rungs: ladder, maxSnoozeCount: 1)
        clock = at(10)
        await engine.handleNotificationResponse(badgerID: id,
                                                actionID: BadgerNotifications.doneActionID,
                                                defaultSnooze: 300)
        #expect(try #require(fetchBadger(id, c)).state == .done)
    }

    @Test("reconcile infers missed soft-rung fires + last-rung repeats, lands at last")
    func reconcileInfersFires() async throws {
        var clock = at(0)
        let c = try makeModelContainer(inMemory: true)
        let engine = BadgerEngine(container: c, registry: AlertChannelRegistry([FakeChannel()]),
                                  repeatBatchSize: 4, now: { clock })
        let id = await engine.create(title: "x", startAt: at(0), rungs: ladder, maxSnoozeCount: 1)
        clock = at(400)
        await engine.reconcile(id)

        let b = try #require(fetchBadger(id, c))
        #expect(b.state == .active)
        #expect(b.currentLevel == 2)
        let kinds = eventKinds(id, c)
        #expect(kinds.contains(.levelFired))
        #expect(kinds.contains(.lastRungRepeated))
        #expect(kinds.last == .reconciled)
    }

    @Test("snooze cancels pending + arms a wake; reconcile after expiry resumes")
    func snoozeThenResume() async throws {
        var clock = at(0)
        let c = try makeModelContainer(inMemory: true)
        let fake = FakeChannel()
        let engine = BadgerEngine(container: c, registry: AlertChannelRegistry([fake]),
                                  repeatBatchSize: 4, now: { clock })
        let id = await engine.create(title: "x", startAt: at(0), rungs: ladder, maxSnoozeCount: 1)
        clock = at(30)
        await engine.snooze(id, duration: 120)

        #expect(await fake.slots.contains(.wake))
        #expect(await fake.cancelledAll.contains(id))
        var b = try #require(fetchBadger(id, c))
        #expect(b.state == .snoozed)
        #expect(b.snoozeUntil == at(150))

        clock = at(150)
        await engine.reconcile(id)
        b = try #require(fetchBadger(id, c))
        #expect(b.state == .active)
        #expect(eventKinds(id, c).contains(.snoozeResumed))
    }

    @Test("an unregistered channel id is skipped, not fatal")
    func unknownChannelSkipped() async throws {
        let clock = at(0)
        let c = try makeModelContainer(inMemory: true)
        let engine = BadgerEngine(container: c,
                                  registry: AlertChannelRegistry([FakeChannel(id: "notification")]),
                                  repeatBatchSize: 2, now: { clock })
        let alarmLadder = [RungSpec(index: 0, delay: 0,
                                    actions: [ChannelAction(channelID: "alarmkit", prominence: .breakthrough)])]
        let id = await engine.create(title: "x", startAt: at(0), rungs: alarmLadder, maxSnoozeCount: 1)

        let b = try #require(fetchBadger(id, c))
        #expect(b.state == .pending)
        #expect(b.armedAlarms.isEmpty)               // alarmkit unregistered → nothing armed
    }

    // MARK: - M3: alarmkit channel wiring

    private var alarmLadder: [RungSpec] {
        [
            RungSpec(index: 0, delay: 0,  actions: [ChannelAction(channelID: "alarmkit", prominence: .breakthrough)]),
            RungSpec(index: 1, delay: 60, actions: [ChannelAction(channelID: "alarmkit", prominence: .breakthrough)]),
        ]
    }

    @Test("alarmkit refs populate armedAlarms including the repeat batch")
    func alarmRefStored() async throws {
        let clock = at(0)
        let c = try makeModelContainer(inMemory: true)
        let engine = BadgerEngine(container: c, registry: AlertChannelRegistry([FakeAlarmChannel()]),
                                  repeatBatchSize: 2, now: { clock })
        let id = await engine.create(title: "x", startAt: at(0), rungs: alarmLadder, maxSnoozeCount: 1)
        let b = try #require(fetchBadger(id, c))
        // base rungs 0 and 1 + the 2-member repeat batch on the last rung (n=1,2). The
        // repeat tail is now persisted — the cold-kill bug was that it was discarded.
        #expect(Set(b.armedAlarms.map(\.slot)) == [
            .rung(0), .rung(1),
            .repeatTail(rung: 1, n: 1), .repeatTail(rung: 1, n: 2),
        ])
        #expect(b.armedAlarms.count == 4)
    }

    @Test("an observed alarm fire advances the Badger (levelFired, observed source)")
    func observedFireAdvances() async throws {
        let clock = at(0)
        let c = try makeModelContainer(inMemory: true)
        let engine = BadgerEngine(container: c, registry: AlertChannelRegistry([FakeAlarmChannel()]),
                                  repeatBatchSize: 2, now: { clock })
        let id = await engine.create(title: "x", startAt: at(0), rungs: alarmLadder, maxSnoozeCount: 1)
        await engine.handleChannelEvent(.levelFired(badgerID: id, rung: 1))
        let b = try #require(fetchBadger(id, c))
        #expect(b.state == .active)
        #expect(b.currentLevel == 1)
        #expect(eventKinds(id, c).contains(.levelFired))
    }

    @Test("an observed repeat-tail fire logs lastRungRepeated")
    func observedRepeatLogsRepeat() async throws {
        let clock = at(0)
        let c = try makeModelContainer(inMemory: true)
        let engine = BadgerEngine(container: c, registry: AlertChannelRegistry([FakeAlarmChannel()]),
                                  repeatBatchSize: 2, now: { clock })
        let id = await engine.create(title: "x", startAt: at(0), rungs: alarmLadder, maxSnoozeCount: 1)
        await engine.handleChannelEvent(.levelFired(badgerID: id, rung: 1))
        await engine.handleChannelEvent(.repeatFired(badgerID: id, rung: 1, n: 1))
        let kinds = eventKinds(id, c)
        #expect(kinds.contains(.lastRungRepeated))
    }

    @Test("an observed dismissal logs but does NOT resolve (§8 dismiss != done)")
    func observedDismissDoesNotResolve() async throws {
        let clock = at(0)
        let c = try makeModelContainer(inMemory: true)
        let engine = BadgerEngine(container: c, registry: AlertChannelRegistry([FakeAlarmChannel()]),
                                  repeatBatchSize: 2, now: { clock })
        let single = [RungSpec(index: 0, delay: 0,
                               actions: [ChannelAction(channelID: "alarmkit", prominence: .breakthrough)])]
        let id = await engine.create(title: "x", startAt: at(0), rungs: single, maxSnoozeCount: 1)
        await engine.handleChannelEvent(.dismissed(badgerID: id, rung: 0))
        let b = try #require(fetchBadger(id, c))
        #expect(b.state == .pending)
        #expect(eventKinds(id, c).contains(.alarmDismissed))
    }
}
