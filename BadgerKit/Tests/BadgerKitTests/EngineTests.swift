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
    // CP2 stray sweep: a settable app-global system set + the enumerate/cancel hooks.
    var systemIdentifiers: [String] = []
    func setSystemIdentifiers(_ ids: [String]) { systemIdentifiers = ids }
    func scheduledIdentifiers() async -> [String] { systemIdentifiers }
    private(set) var cancelledIdentifiers: [String] = []
    func cancel(identifiers: [String]) async { cancelledIdentifiers.append(contentsOf: identifiers) }

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
    private(set) var cancelledIdentifiers: [String] = []
    private(set) var issuedIdentifiers: [String] = []
    // CP2 stray sweep: settable app-global system set the enumerate hook returns.
    var systemIdentifiers: [String] = []
    func setSystemIdentifiers(_ ids: [String]) { systemIdentifiers = ids }
    func scheduledIdentifiers() async -> [String] { systemIdentifiers }
    func schedule(_ action: ChannelAction, at fireDate: Date, recurrence: ChannelRecurrence?,
                  badgerID: UUID, slot: ScheduleSlot) async throws -> ScheduledRef {
        scheduled.append(slot)
        let identifier = UUID().uuidString
        issuedIdentifiers.append(identifier)
        return ScheduledRef(channelID: id, identifier: identifier, slot: slot)
    }
    func cancel(_ ref: ScheduledRef) async {}
    func cancelAll(forBadgerID badgerID: UUID) async {}
    // owners-free: records the ids the engine asks us to cancel (the cold-kill path).
    func cancel(identifiers: [String]) async { cancelledIdentifiers.append(contentsOf: identifiers) }
    private(set) var adopted: [(badgerID: UUID, refs: [ArmedRef])] = []
    func adopt(badgerID: UUID, refs: [ArmedRef]) async { adopted.append((badgerID, refs)) }
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

    @Test("cancel routes persisted armedAlarms ids to the channel (cold-kill-safe), then clears")
    func cancelUsesPersistedIDs() async throws {
        let clock = at(0)
        let c = try makeModelContainer(inMemory: true)
        let fake = FakeAlarmChannel()
        let engine = BadgerEngine(container: c, registry: AlertChannelRegistry([fake]),
                                  repeatBatchSize: 2, now: { clock })
        let id = await engine.create(title: "x", startAt: at(0), rungs: alarmLadder, maxSnoozeCount: 1)
        let armed = Set(try #require(fetchBadger(id, c)).armedAlarms.map(\.id))
        #expect(armed.count == 4)                    // rungs 0,1 + 2 repeat-tail

        await engine.markDone(id)

        // FakeAlarmChannel.cancelAll is a no-op (the cold-kill case: empty owners map),
        // yet every persisted id was cancelled via cancel(identifiers:).
        #expect(Set(await fake.cancelledIdentifiers) == armed)
        #expect(try #require(fetchBadger(id, c)).armedAlarms.isEmpty)   // cleared after teardown
    }

    @Test("rehydrate re-adopts non-terminal Badgers' armed alarms; skips terminal")
    func rehydrateAdopts() async throws {
        let clock = at(0)
        let c = try makeModelContainer(inMemory: true)
        let fake = FakeAlarmChannel()
        let engine = BadgerEngine(container: c, registry: AlertChannelRegistry([fake]),
                                  repeatBatchSize: 2, now: { clock })
        let id = await engine.create(title: "x", startAt: at(0), rungs: alarmLadder, maxSnoozeCount: 1)
        let armed = try #require(fetchBadger(id, c)).armedAlarms

        await engine.rehydrateArmedAlarms()

        let adopted = await fake.adopted
        #expect(adopted.count == 1)
        #expect(adopted.first?.badgerID == id)
        #expect(Set((adopted.first?.refs ?? []).map(\.id)) == Set(armed.map(\.id)))

        // A resolved Badger (armedAlarms cleared + terminal) is not re-adopted.
        await engine.markDone(id)
        await engine.rehydrateArmedAlarms()
        #expect(await fake.adopted.count == 1)
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

    // MARK: - M6 CP1: reconcile replenishment + re-arm

    @Test("reconcile replenishes the alarmkit repeat batch and prunes consumed refs")
    func reconcileReplenishesAlarmBatch() async throws {
        var clock = at(0)
        let c = try makeModelContainer(inMemory: true)
        let fake = FakeAlarmChannel()
        let engine = BadgerEngine(container: c, registry: AlertChannelRegistry([fake]),
                                  repeatBatchSize: 4, now: { clock })
        // alarmLadder: rung0 @0, rung1 @60 (last). interval 60, firstLastFire 60; rep n @ 60+n*60.
        let id = await engine.create(title: "x", startAt: at(0), rungs: alarmLadder, maxSnoozeCount: 1)

        func repNs(_ b: Badger) -> Set<Int> {
            Set(b.armedAlarms.compactMap { if case .repeatTail(_, let n) = $0.slot { return n } else { return nil } })
        }
        #expect(repNs(try #require(fetchBadger(id, c))) == [1, 2, 3, 4])   // initial batch

        // Jump past repeats 1(@120),2(@180),3(@240); next future occurrence is n=4(@300).
        clock = at(250)
        await engine.reconcile(id)

        let b = try #require(fetchBadger(id, c))
        #expect(b.currentLevel == 1)                       // caught up to the last rung
        #expect(repNs(b) == [4, 5, 6, 7])                  // 1–3 pruned, topped up to the next 4
    }

    @Test("reconcile replenishes the notification repeat batch by deterministic id (idempotent)")
    func reconcileReplenishesNotificationBatch() async throws {
        var clock = at(0)
        let c = try makeModelContainer(inMemory: true)
        let fake = FakeChannel()   // id "notification"
        let engine = BadgerEngine(container: c, registry: AlertChannelRegistry([fake]),
                                  repeatBatchSize: 4, now: { clock })
        // ladder last = rung2 @180. interval 120, firstLastFire 180; rep n @ 180+n*120.
        let id = await engine.create(title: "x", startAt: at(0), rungs: ladder, maxSnoozeCount: 1)

        // now 700 → repeats 1(@300)…4(@660) past; next future window is n=5…8.
        clock = at(700)
        await engine.reconcile(id)

        let scheduledReps = await fake.scheduled.compactMap {
            if case .repeatTail(_, let n) = $0.slot { return n } else { return nil }
        }
        #expect(Set(scheduledReps).isSuperset(of: [5, 6, 7, 8]))   // topped-up window re-armed
        #expect(try #require(fetchBadger(id, c)).currentLevel == 2)
        #expect(try #require(fetchBadger(id, c)).armedAlarms.isEmpty)  // notifications aren't persisted
    }

    // MARK: - M6 CP2: backstop stray sweep

    @Test("sweep cancels a system alarm no live Badger owns, keeps owned ones")
    func sweepCancelsUnownedAlarm() async throws {
        let clock = at(0)
        let c = try makeModelContainer(inMemory: true)
        let fake = FakeAlarmChannel()
        let engine = BadgerEngine(container: c, registry: AlertChannelRegistry([fake]),
                                  repeatBatchSize: 2, now: { clock })
        let id = await engine.create(title: "x", startAt: at(0), rungs: alarmLadder, maxSnoozeCount: 1)

        // The live Badger owns exactly the ids the fake issued at arm time; add an orphan the app
        // scheduled but no live Badger claims (a crash-window / lost-row straggler).
        let owned = await fake.issuedIdentifiers
        let orphan = UUID().uuidString
        await fake.setSystemIdentifiers(owned + [orphan])

        await engine.sweepStrayAlerts()

        #expect(await fake.cancelledIdentifiers == [orphan])                                // orphan swept
        #expect(Set(try #require(fetchBadger(id, c)).armedAlarms.map(\.id)) == Set(owned))  // owned kept
    }

    @Test("sweep reaches an orphan of a resolved (terminal) Badger — the crash-window straggler")
    func sweepClearsTerminalOrphan() async throws {
        var clock = at(0)
        let c = try makeModelContainer(inMemory: true)
        let fake = FakeAlarmChannel()
        let engine = BadgerEngine(container: c, registry: AlertChannelRegistry([fake]),
                                  repeatBatchSize: 2, now: { clock })
        let id = await engine.create(title: "x", startAt: at(0), rungs: alarmLadder, maxSnoozeCount: 1)
        clock = at(30)
        await engine.markDone(id)                                  // terminal; armedAlarms cleared

        let orphan = UUID().uuidString                             // a straggler teardown missed
        #expect(!(await fake.cancelledIdentifiers.contains(orphan)))
        await fake.setSystemIdentifiers([orphan])
        await engine.sweepStrayAlerts()
        #expect(await fake.cancelledIdentifiers.contains(orphan))
    }

    @Test("sweep cancels pending notifications of a dead Badger by namespace, keeps a live one")
    func sweepNotificationNamespace() async throws {
        let clock = at(0)
        let c = try makeModelContainer(inMemory: true)
        let fake = FakeChannel()   // id "notification"
        let engine = BadgerEngine(container: c, registry: AlertChannelRegistry([fake]),
                                  repeatBatchSize: 2, now: { clock })
        let liveID = await engine.create(title: "live", startAt: at(0), rungs: ladder, maxSnoozeCount: 1)
        let deadID = UUID()   // a Badger whose row no longer exists

        await fake.setSystemIdentifiers([
            BadgerNotifications.identifier(badgerID: liveID, slot: .rung(0)),
            BadgerNotifications.identifier(badgerID: deadID, slot: .rung(0)),
            BadgerNotifications.identifier(badgerID: deadID, slot: .wake),
        ])
        await engine.sweepStrayAlerts()

        #expect(Set(await fake.cancelledIdentifiers) == [
            BadgerNotifications.identifier(badgerID: deadID, slot: .rung(0)),
            BadgerNotifications.identifier(badgerID: deadID, slot: .wake),
        ])
    }

    // MARK: - M6 CP3: snooze-all control

    @Test("snoozeAllActive snoozes only escalating (.active) Badgers, not pending")
    func snoozeAllActiveOnlyActive() async throws {
        let clock = at(0)
        let c = try makeModelContainer(inMemory: true)
        let engine = BadgerEngine(container: c, registry: AlertChannelRegistry([FakeChannel()]),
                                  repeatBatchSize: 2, now: { clock })
        let a = await engine.create(title: "a", startAt: at(0), rungs: ladder, maxSnoozeCount: 1)
        let b = await engine.create(title: "b", startAt: at(0), rungs: ladder, maxSnoozeCount: 1)
        let pending = await engine.create(title: "p", startAt: at(0), rungs: ladder, maxSnoozeCount: 1)
        await engine.handleChannelEvent(.levelFired(badgerID: a, rung: 0))
        await engine.handleChannelEvent(.levelFired(badgerID: b, rung: 0))
        #expect(try #require(fetchBadger(a, c)).state == .active)
        #expect(try #require(fetchBadger(pending, c)).state == .pending)

        await engine.snoozeAllActive(duration: 600)

        #expect(try #require(fetchBadger(a, c)).state == .snoozed)
        #expect(try #require(fetchBadger(b, c)).state == .snoozed)
        #expect(try #require(fetchBadger(pending, c)).state == .pending)   // untouched
    }
}
