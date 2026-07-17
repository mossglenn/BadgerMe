//
//  ScheduleReplenishTests.swift
//  BadgerKitTests — the pure `forwardSlots` decision for reconcile replenishment
//  (§14, M6 CP1). No channels, no container: exact clock-driven assertions, the
//  pattern of AlarmSnapshotDiffTests (M3 review #4).
//
//  Ladder throughout: rung0 @ +0s, rung1 @ +60s, rung2 @ +180s (last).
//  => repeat interval = rung2.delay - rung1.delay = 120s; nth repeat fires at 180 + n*120.
//

import Testing
import Foundation
@testable import BadgerKit

@Suite("BadgerKit forwardSlots (reconcile replenishment, §14/M6 CP1)")
struct ScheduleReplenishTests {

    private let T0 = Date(timeIntervalSinceReferenceDate: 0)
    private func at(_ s: TimeInterval) -> Date { T0.addingTimeInterval(s) }

    private let ladder = [
        Rung(index: 0, delay: 0),
        Rung(index: 1, delay: 60),
        Rung(index: 2, delay: 180),
    ]
    private func ctx(_ now: TimeInterval) -> Context {
        Context(now: at(now), rungs: ladder, maxSnoozeCount: 1)
    }
    private func repeatNs(_ slots: [ScheduleSlot]) -> [Int] {
        slots.compactMap { if case .repeatTail(_, let n) = $0 { return n } else { return nil } }
    }
    private func rungKs(_ slots: [ScheduleSlot]) -> [Int] {
        slots.compactMap { if case .rung(let k) = $0 { return k } else { return nil } }
    }

    // MARK: - Repeating (active at the last rung)

    @Test("active(last): the next repeatBatchSize repeats, no base rungs, window from now")
    func repeatingWindowFromNow() {
        let st = MachineState(status: .active(level: 2), startAt: at(0), snoozeCount: 0)
        // just reached last (firstLastFire = 180): first future repeat is n=1.
        let atReach = forwardSlots(state: st, ctx: ctx(180), repeatBatchSize: 4)
        #expect(rungKs(atReach).isEmpty)
        #expect(repeatNs(atReach) == [1, 2, 3, 4])

        // now = 500 → firstFuture = floor((500-180)/120)+1 = 3 → [3,4,5,6].
        #expect(repeatNs(forwardSlots(state: st, ctx: ctx(500), repeatBatchSize: 4)) == [3, 4, 5, 6])
    }

    @Test("active(last): the repeat window advances as now crosses each occurrence")
    func repeatWindowShifts() {
        let st = MachineState(status: .active(level: 2), startAt: at(0), snoozeCount: 0)
        // rep n fires at 180 + n*120: n=1@300, n=2@420, n=3@540.
        #expect(repeatNs(forwardSlots(state: st, ctx: ctx(180), repeatBatchSize: 3)) == [1, 2, 3])
        #expect(repeatNs(forwardSlots(state: st, ctx: ctx(300), repeatBatchSize: 3)) == [2, 3, 4]) // crossed n=1
        #expect(repeatNs(forwardSlots(state: st, ctx: ctx(420), repeatBatchSize: 3)) == [3, 4, 5]) // crossed n=2
    }

    // MARK: - Escalating (active below the last rung)

    @Test("active(k<last): only future base rungs above k, no repeats yet")
    func escalatingFutureRungs() {
        let st = MachineState(status: .active(level: 0), startAt: at(0), snoozeCount: 0)
        let slots = forwardSlots(state: st, ctx: ctx(30), repeatBatchSize: 4)  // before rung1@60
        #expect(rungKs(slots) == [1, 2])
        #expect(repeatNs(slots).isEmpty)
    }

    @Test("active(k<last): a base rung whose time already passed is not re-armed")
    func escalatingSkipsPastRung() {
        let st = MachineState(status: .active(level: 0), startAt: at(0), snoozeCount: 0)
        // now = 120: rung1@60 is past, rung2@180 still future → only rung2.
        let slots = forwardSlots(state: st, ctx: ctx(120), repeatBatchSize: 4)
        #expect(rungKs(slots) == [2])
        #expect(repeatNs(slots).isEmpty)
    }

    // MARK: - Pending / terminal / snoozed

    @Test("pending: future base rungs including rung 0")
    func pendingArmsFromZero() {
        let st = MachineState(status: .pending, startAt: at(100), snoozeCount: 0)
        let slots = forwardSlots(state: st, ctx: ctx(50), repeatBatchSize: 4)  // before rung0@100
        #expect(rungKs(slots) == [0, 1, 2])
        #expect(repeatNs(slots).isEmpty)
    }

    @Test("terminal and snoozed arm nothing")
    func terminalAndSnoozedEmpty() {
        let done = MachineState(status: .done, startAt: at(0), snoozeCount: 0)
        #expect(forwardSlots(state: done, ctx: ctx(500), repeatBatchSize: 4).isEmpty)

        let stopped = MachineState(status: .stopped, startAt: at(0), snoozeCount: 0)
        #expect(forwardSlots(state: stopped, ctx: ctx(500), repeatBatchSize: 4).isEmpty)

        let snoozed = MachineState(status: .snoozed(until: at(600), resumeLevel: 1),
                                   startAt: at(0), snoozeCount: 1)
        #expect(forwardSlots(state: snoozed, ctx: ctx(300), repeatBatchSize: 4).isEmpty)
    }

    @Test("the repeat batch is exactly repeatBatchSize wide")
    func batchWidth() {
        let st = MachineState(status: .active(level: 2), startAt: at(0), snoozeCount: 0)
        #expect(repeatNs(forwardSlots(state: st, ctx: ctx(1000), repeatBatchSize: 8)).count == 8)
        #expect(repeatNs(forwardSlots(state: st, ctx: ctx(1000), repeatBatchSize: 1)).count == 1)
    }
}
