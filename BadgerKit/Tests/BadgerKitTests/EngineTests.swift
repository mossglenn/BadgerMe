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
        #expect(b.armedNotificationIDs.count == 3)
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
        #expect(b.armedNotificationIDs.isEmpty)
    }
}
