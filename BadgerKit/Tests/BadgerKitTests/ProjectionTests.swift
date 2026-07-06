//
//  ProjectionTests.swift
//  BadgerKitTests — MachineState <-> Badger projection, log translation, replay (§6/§7/§18).
//

import Testing
import Foundation
@testable import BadgerKit

@Suite("BadgerKit projection (Phase 5 §6/§7/§18)")
@MainActor
struct ProjectionTests {

    private let T0 = Date(timeIntervalSinceReferenceDate: 0)
    private func at(_ s: TimeInterval) -> Date { T0.addingTimeInterval(s) }

    private func badger(state: StoredBadgerState, level: Int = 0,
                        snoozeCount: Int = 0, snoozeUntil: Date? = nil,
                        startAt: Date? = nil) -> Badger {
        Badger(title: "b", startAt: startAt ?? T0, state: state,
               currentLevel: level, snoozeCount: snoozeCount,
               snoozeUntil: snoozeUntil, maxSnoozeCount: 1)
    }

    // MARK: MachineState(from:)

    @Test("Pending Badger projects to pending")
    func fromPending() {
        let s = MachineState(from: badger(state: .pending))
        #expect(s.status == .pending)
        #expect(s.startAt == T0)
    }

    @Test("Active Badger projects to active(currentLevel)")
    func fromActive() {
        #expect(MachineState(from: badger(state: .active, level: 2)).status == .active(level: 2))
    }

    @Test("Snoozed Badger reconstructs until + resumeLevel from snoozeUntil + currentLevel")
    func fromSnoozed() {
        let s = MachineState(from: badger(state: .snoozed, level: 1, snoozeUntil: at(210)))
        #expect(s.status == .snoozed(until: at(210), resumeLevel: 1))
    }

    @Test("Done and Stopped project to their terminal states")
    func fromTerminal() {
        #expect(MachineState(from: badger(state: .done)).status == .done)
        #expect(MachineState(from: badger(state: .stopped)).status == .stopped)
    }

    // MARK: apply(_:to:)

    @Test("apply writes an active state back onto the cache")
    func applyActive() {
        let b = badger(state: .pending)
        apply(MachineState(status: .active(level: 2), startAt: at(100), snoozeCount: 0), to: b)
        #expect(b.state == .active)
        #expect(b.currentLevel == 2)
        #expect(b.startAt == at(100))
        #expect(b.snoozeUntil == nil)
    }

    @Test("apply writes a snoozed state (snoozeUntil + resumeLevel) back")
    func applySnoozed() {
        let b = badger(state: .active, level: 1)
        apply(MachineState(status: .snoozed(until: at(360), resumeLevel: 1),
                           startAt: T0, snoozeCount: 2), to: b)
        #expect(b.state == .snoozed)
        #expect(b.currentLevel == 1)
        #expect(b.snoozeUntil == at(360))
        #expect(b.snoozeCount == 2)
    }

    @Test("apply sets the terminal discriminator")
    func applyTerminal() {
        let b = badger(state: .active, level: 2)
        apply(MachineState(status: .done, startAt: T0, snoozeCount: 0), to: b)
        #expect(b.state == .done)
        apply(MachineState(status: .stopped, startAt: T0, snoozeCount: 0), to: b)
        #expect(b.state == .stopped)
    }

    @Test("Badger -> MachineState -> apply round-trips the non-terminal states")
    func roundTrip() {
        let cases: [Badger] = [
            badger(state: .pending),
            badger(state: .active, level: 3, startAt: at(50)),
            badger(state: .snoozed, level: 1, snoozeCount: 2, snoozeUntil: at(210)),
        ]
        for original in cases {
            let s = MachineState(from: original)
            let copy = badger(state: .pending)
            copy.currentLevel = original.currentLevel
            apply(s, to: copy)
            #expect(copy.state == original.state)
            #expect(copy.currentLevel == original.currentLevel)
            #expect(copy.snoozeUntil == original.snoozeUntil)
            #expect(copy.startAt == original.startAt)
            #expect(MachineState(from: copy).status == s.status)
        }
    }

    // MARK: LoggedEvent -> EventRecord

    @Test("makeEventRecord copies kind/level/source/detail and engine-assigned fields")
    func logTranslation() {
        let logged = LoggedEvent(kind: .lastRungRepeated, level: 2,
                                 detail: ["repeat": "1"], source: .observed)
        let id = UUID()
        let rec = makeEventRecord(from: logged, badgerID: id, sequence: 7, timestamp: at(480))
        #expect(rec.kind == .lastRungRepeated)
        #expect(rec.level == 2)
        #expect(rec.source == .observed)
        #expect(rec.detail["repeat"] == "1")
        #expect(rec.badgerID == id)
        #expect(rec.sequence == 7)
        #expect(rec.timestamp == at(480))
    }

    // MARK: fold / replay (§18 C-seam)

    @Test("Folding a scripted event stream derives the same end state as step-by-step")
    func foldReplay() {
        let ladder = [Rung(index: 0, delay: 0), Rung(index: 1, delay: 60), Rung(index: 2, delay: 180)]
        func ctx(_ now: TimeInterval) -> Context { Context(now: at(now), rungs: ladder, maxSnoozeCount: 1) }
        let steps: [(event: Event, context: Context)] = [
            (.created(startAt: at(0)), ctx(0)),
            (.levelFired(level: 0, source: .observed), ctx(0)),
            (.levelFired(level: 1, source: .observed), ctx(60)),
            (.levelFired(level: 2, source: .observed), ctx(180)),
        ]
        #expect(foldEvents(steps).status == .active(level: 2))
    }
}
