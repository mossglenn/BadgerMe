//
//  EngineLiveActivityTests.swift
//  BadgerKitTests — the engine forwards the right ambient Live-Activity calls (§12/§18).
//
//  The reducer tests already assert the correct start/update/end EFFECTS are emitted per
//  transition; these assert the ENGINE forwards them to its LiveActivityControlling with the
//  right phase + currentLevelIndex + totalLevels (sourced from the bound ladder at dispatch,
//  which the reducer effect does NOT carry) + fixed nextFireDate — across create / escalate /
//  repeat / snooze / done and the reconcile catch-up path. A RecordingLiveActivityController
//  stands in for the ActivityKit controller (which is iOS-only / device-verified).
//

import Testing
import Foundation
import SwiftData
@testable import BadgerKit

/// Records the ambient Live-Activity calls the engine makes (no ActivityKit).
actor RecordingLiveActivityController: LiveActivityControlling {
    enum Call: Equatable {
        case start(badgerID: UUID, tint: String?, iconName: String?, phase: BadgerActivityPhase, level: Int, totalLevels: Int, nextFire: Date?)
        case update(badgerID: UUID, phase: BadgerActivityPhase, level: Int, totalLevels: Int, nextFire: Date?)
        case end(badgerID: UUID, terminalPhase: BadgerActivityPhase?)
    }
    private(set) var calls: [Call] = []
    func start(badgerID: UUID, title: String, tint: String?, iconName: String?, phase: BadgerActivityPhase,
               level: Int, totalLevels: Int, nextFire: Date?) async {
        calls.append(.start(badgerID: badgerID, tint: tint, iconName: iconName, phase: phase, level: level,
                            totalLevels: totalLevels, nextFire: nextFire))
    }
    func update(badgerID: UUID, phase: BadgerActivityPhase,
                level: Int, totalLevels: Int, nextFire: Date?) async {
        calls.append(.update(badgerID: badgerID, phase: phase, level: level,
                             totalLevels: totalLevels, nextFire: nextFire))
    }
    func end(badgerID: UUID, terminalPhase: BadgerActivityPhase?) async { calls.append(.end(badgerID: badgerID, terminalPhase: terminalPhase)) }

    var updates: [Call] { calls.filter { if case .update = $0 { return true } else { return false } } }
}

@Suite("BadgerKit engine — ambient Live Activity dispatch (§12)")
@MainActor
struct EngineLiveActivityTests {

    private let T0 = Date(timeIntervalSinceReferenceDate: 0)
    private func at(_ s: TimeInterval) -> Date { T0.addingTimeInterval(s) }

    // rung0 @ +0, rung1 @ +60, rung2 @ +180 (last). Repeat interval = 120. totalLevels = 3.
    private var ladder: [RungSpec] {
        [
            RungSpec(index: 0, delay: 0,   actions: [ChannelAction(channelID: "notification", prominence: .active)]),
            RungSpec(index: 1, delay: 60,  actions: [ChannelAction(channelID: "notification", prominence: .timeSensitive)]),
            RungSpec(index: 2, delay: 120, actions: [ChannelAction(channelID: "notification", prominence: .timeSensitive)]),
        ]
    }

    private func makeEngine(_ recorder: RecordingLiveActivityController,
                            now: @escaping () -> Date) throws -> BadgerEngine {
        let c = try makeModelContainer(inMemory: true)
        return BadgerEngine(container: c, registry: AlertChannelRegistry([FakeChannel()]),
                            liveActivity: recorder, repeatBatchSize: 4, now: now)
    }

    @Test("create starts the ambient activity: armed, level 0, totalLevels from the ladder")
    func createStarts() async throws {
        let rec = RecordingLiveActivityController()
        let engine = try makeEngine(rec, now: { self.at(0) })
        let id = await engine.create(title: "t", startAt: at(0), rungs: ladder, maxSnoozeCount: 1)
        #expect(await rec.calls == [.start(badgerID: id, tint: "accent", iconName: nil, phase: .armed, level: 0,
                                           totalLevels: 3, nextFire: at(0))])
    }

    @Test("create forwards the Badger's tint + icon to the ambient activity (code review #6)")
    func createForwardsTintAndIcon() async throws {
        let rec = RecordingLiveActivityController()
        let engine = try makeEngine(rec, now: { self.at(0) })
        let id = await engine.create(title: "t", startAt: at(0), rungs: ladder, maxSnoozeCount: 1,
                                     tint: "teal", iconName: "pills.fill")
        #expect(await rec.calls == [.start(badgerID: id, tint: "teal", iconName: "pills.fill",
                                           phase: .armed, level: 0, totalLevels: 3, nextFire: at(0))])
    }

    @Test("escalating fires advance the card's level + nextFire")
    func escalationUpdates() async throws {
        var clock = at(0)
        let rec = RecordingLiveActivityController()
        let engine = try makeEngine(rec, now: { clock })
        let id = await engine.create(title: "t", startAt: at(0), rungs: ladder, maxSnoozeCount: 1)
        await engine.handleChannelEvent(.levelFired(badgerID: id, rung: 0))
        clock = at(60)
        await engine.handleChannelEvent(.levelFired(badgerID: id, rung: 1))
        #expect(await rec.updates == [
            .update(badgerID: id, phase: .escalating, level: 0, totalLevels: 3, nextFire: at(60)),
            .update(badgerID: id, phase: .escalating, level: 1, totalLevels: 3, nextFire: at(180)),
        ])
    }

    @Test("reaching the last rung switches the card to the repeating phase")
    func lastRungRepeating() async throws {
        var clock = at(0)
        let rec = RecordingLiveActivityController()
        let engine = try makeEngine(rec, now: { clock })
        let id = await engine.create(title: "t", startAt: at(0), rungs: ladder, maxSnoozeCount: 1)
        await engine.handleChannelEvent(.levelFired(badgerID: id, rung: 0))
        clock = at(60);  await engine.handleChannelEvent(.levelFired(badgerID: id, rung: 1))
        clock = at(180); await engine.handleChannelEvent(.levelFired(badgerID: id, rung: 2))
        #expect(await rec.updates.last == .update(badgerID: id, phase: .repeating, level: 2,
                                                  totalLevels: 3, nextFire: at(300)))
    }

    @Test("snooze shows the snoozed phase to the resume time; done ends the activity")
    func snoozeThenDone() async throws {
        var clock = at(0)
        let rec = RecordingLiveActivityController()
        let engine = try makeEngine(rec, now: { clock })
        let id = await engine.create(title: "t", startAt: at(0), rungs: ladder, maxSnoozeCount: 1)
        await engine.handleChannelEvent(.levelFired(badgerID: id, rung: 0))   // active(0)
        clock = at(30)
        await engine.snooze(id, duration: 120)                                // snoozed until +150
        #expect(await rec.updates.last == .update(badgerID: id, phase: .snoozed, level: 0,
                                                  totalLevels: 3, nextFire: at(150)))
        clock = at(40)
        await engine.markDone(id)
        #expect(await rec.calls.last == .end(badgerID: id, terminalPhase: .done))
    }

    @Test("reconcile after backgrounding refreshes the card to the caught-up repeating state")
    func reconcileRefreshes() async throws {
        var clock = at(0)
        let rec = RecordingLiveActivityController()
        let engine = try makeEngine(rec, now: { clock })
        let id = await engine.create(title: "t", startAt: at(0), rungs: ladder, maxSnoozeCount: 1)
        await engine.handleChannelEvent(.levelFired(badgerID: id, rung: 0))   // active(0)
        clock = at(400)
        await engine.reconcile(id)
        // catch-up: rung1@+60, rung2@+180 fired; first repeat @+300; next @+420 > 400.
        #expect(await rec.updates.last == .update(badgerID: id, phase: .repeating, level: 2,
                                                  totalLevels: 3, nextFire: at(420)))
    }

    @Test("undo (reopenDone) restarts the ambient card at the preserved level")
    func reopenRestartsCard() async throws {
        var clock = at(0)
        let rec = RecordingLiveActivityController()
        let engine = try makeEngine(rec, now: { clock })
        let id = await engine.create(title: "t", startAt: at(0), rungs: ladder, maxSnoozeCount: 1)
        await engine.handleChannelEvent(.levelFired(badgerID: id, rung: 0))          // active(0)
        clock = at(60);  await engine.handleChannelEvent(.levelFired(badgerID: id, rung: 1))  // active(1)
        clock = at(90);  await engine.markDone(id)                                   // done; currentLevel preserved (1)
        #expect(await rec.calls.last == .end(badgerID: id, terminalPhase: .done))

        // Undo at +200: reopenDone defaults toLevel to the preserved currentLevel (1).
        // startAt' = 200 − rung1.delay(60) = 140; next rung(2) fires at 140 + 180 = 320.
        clock = at(200)
        let snap = await engine.reopenDone(id)
        #expect(await rec.calls.last == .start(badgerID: id, tint: "accent", iconName: nil,
                                               phase: .escalating, level: 1, totalLevels: 3, nextFire: at(320)))
        #expect(snap?.state == .active)
        #expect(snap?.currentLevel == 1)
    }
}
