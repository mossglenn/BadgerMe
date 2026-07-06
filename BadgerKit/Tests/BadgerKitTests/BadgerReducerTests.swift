//
//  BadgerReducerTests.swift
//  BadgerKitTests — the executable spec for the Phase 5 §8 state machine
//
//  These tests ARE the acceptance criteria for milestone M1. The first test is the
//  GOLDEN PATH: one Badger traced end to end (create -> escalate -> snooze/hold ->
//  snooze/escalate-to-last -> repeat -> done), asserting state and the load-bearing
//  effects at every step. The remaining tests pin individual rows of §8.
//
//  Pure and deterministic: time is injected via Context.now, so every assertion is
//  an exact value — no sleeps, no flakiness, no system frameworks.
//
//  Ladder used throughout: rung0 @ +0s, rung1 @ +60s, rung2 @ +180s (the last rung).
//  => repeat interval = rung2.delay - rung1.delay = 120s.
//

import Testing
import Foundation
@testable import BadgerKit

@Suite("BadgerMe reducer (Phase 5 §8)")
struct BadgerReducerTests {

    // MARK: Fixtures

    private let T0 = Date(timeIntervalSinceReferenceDate: 0)
    private func at(_ s: TimeInterval) -> Date { T0.addingTimeInterval(s) }

    private let ladder = [
        Rung(index: 0, delay: 0),
        Rung(index: 1, delay: 60),
        Rung(index: 2, delay: 180),
    ]
    private func ctx(_ now: TimeInterval, maxSnooze: Int = 1) -> Context {
        Context(now: at(now), rungs: ladder, maxSnoozeCount: maxSnooze)
    }

    // MARK: - GOLDEN PATH (the anchor)

    @Test("Golden path: create → escalate → snooze/hold → snooze/escalate → repeat → done")
    func goldenPath() {
        var st = MachineState.seed
        var fx: [Effect] = []

        // 1. Created at T0 → pending; the whole ladder + repeat is armed; LA starts.
        (st, fx) = reduce(st, .created(startAt: at(0)), ctx(0))
        #expect(st.status == .pending)
        #expect(st.startAt == at(0))
        #expect(st.snoozeCount == 0)
        #expect(fx.contains(.append(LoggedEvent(kind: .created, source: .userAction))))
        #expect(fx.contains(.append(LoggedEvent(kind: .armed, source: .system))))
        #expect(fx.contains(.armSchedule(fromLevel: 0)))
        #expect(fx.contains(.startLiveActivity(phase: .armed, nextFire: at(0))))  // rung0 @ +0

        // 2. Rung 0 fires at T0 → active(0); countdown now targets rung1 (+60).
        (st, fx) = reduce(st, .levelFired(level: 0, source: .observed), ctx(0))
        #expect(st.status == .active(level: 0))
        #expect(fx.contains(.updateLiveActivity(phase: .escalating, level: 0, nextFire: at(60))))

        // 3. Rung 1 fires at +60 → active(1); countdown targets rung2 (+180).
        (st, fx) = reduce(st, .levelFired(level: 1, source: .observed), ctx(60))
        #expect(st.status == .active(level: 1))
        #expect(fx.contains(.updateLiveActivity(phase: .escalating, level: 1, nextFire: at(180))))

        // 4. User snoozes 120s at +90 → snoozed until +210, resume level 1; wake armed.
        (st, fx) = reduce(st, .userSnoozed(duration: 120), ctx(90))
        #expect(st.status == .snoozed(until: at(210), resumeLevel: 1))
        #expect(st.snoozeCount == 1)
        #expect(fx.contains(.cancelAllPending))
        #expect(fx.contains(.armWake(at: at(210))))

        // 5. Snooze expires at +210. snoozeCount(1) is NOT over the cap(1) → hold at
        //    level 1. Schedule re-anchors (startAt' = 210 − 60 = 150) so rung2 is +330.
        (st, fx) = reduce(st, .snoozeExpired, ctx(210))
        #expect(st.status == .active(level: 1))
        #expect(st.startAt == at(150))
        #expect(st.snoozeCount == 1)                                     // held, not reset
        #expect(fx.contains(.append(LoggedEvent(kind: .snoozeResumed, level: 1, source: .system))))
        #expect(!fx.contains(.append(LoggedEvent(kind: .snoozeEscalated, level: 1, source: .system))))
        #expect(fx.contains(.updateLiveActivity(phase: .escalating, level: 1, nextFire: at(330))))

        // 6. User snoozes again 120s at +240 → snoozed until +360; count now 2.
        (st, fx) = reduce(st, .userSnoozed(duration: 120), ctx(240))
        #expect(st.status == .snoozed(until: at(360), resumeLevel: 1))
        #expect(st.snoozeCount == 2)

        // 7. Snooze expires at +360. snoozeCount(2) > cap(1) → ESCALATE to the last
        //    rung (2). Count resets; phase becomes repeating; next repeat is +480.
        (st, fx) = reduce(st, .snoozeExpired, ctx(360))
        #expect(st.status == .active(level: 2))
        #expect(st.startAt == at(180))                                   // 360 − rung2.delay(180)
        #expect(st.snoozeCount == 0)                                     // advanced → reset
        #expect(fx.contains(.append(LoggedEvent(kind: .snoozeResumed, level: 2, source: .system))))
        #expect(fx.contains(.append(LoggedEvent(kind: .snoozeEscalated, level: 2, source: .system))))
        #expect(fx.contains(.updateLiveActivity(phase: .repeating, level: 2, nextFire: at(480))))

        // 8. The last rung repeats (1st repeat) at +480 → still active(2), repeating;
        //    next repeat is +600.
        (st, fx) = reduce(st, .lastRungRepeated(index: 1, source: .observed), ctx(480))
        #expect(st.status == .active(level: 2))
        #expect(fx.contains(.append(LoggedEvent(kind: .lastRungRepeated, level: 2,
                                                detail: ["repeat": "1"], source: .observed))))
        #expect(fx.contains(.updateLiveActivity(phase: .repeating, level: 2, nextFire: at(600))))

        // 9. User finally marks Done at +500 → terminal; everything torn down.
        (st, fx) = reduce(st, .userMarkedDone, ctx(500))
        #expect(st.status == .done)
        #expect(fx.contains(.cancelAllPending))
        #expect(fx.contains(.append(LoggedEvent(kind: .userMarkedDone, source: .userAction))))
        #expect(fx.contains(.endLiveActivity))
    }

    // MARK: - Creation & first fire

    @Test("Created arms the ladder and pends")
    func createdArmsAndPends() {
        let (st, fx) = reduce(.seed, .created(startAt: at(0)), ctx(0))
        #expect(st.status == .pending)
        #expect(fx.contains(.armSchedule(fromLevel: 0)))
    }

    @Test("First rung fire activates the Badger")
    func firstFireActivates() {
        let (p, _) = reduce(.seed, .created(startAt: at(0)), ctx(0))
        let (st, fx) = reduce(p, .levelFired(level: 0, source: .observed), ctx(0))
        #expect(st.status == .active(level: 0))
        #expect(fx.contains(.updateLiveActivity(phase: .escalating, level: 0, nextFire: at(60))))
    }

    // MARK: - Escalation & the repeat

    @Test("Escalates rung by rung, then enters the repeating phase at the last rung")
    func escalatesToRepeating() {
        var st = MachineState(status: .active(level: 0), startAt: at(0), snoozeCount: 0)
        (st, _) = reduce(st, .levelFired(level: 1, source: .observed), ctx(60))
        #expect(st.status == .active(level: 1))

        let (st2, fx2) = reduce(st, .levelFired(level: 2, source: .observed), ctx(180))
        #expect(st2.status == .active(level: 2))
        // First repeat is one interval (120s) after the last rung's first fire (+180).
        #expect(fx2.contains(.updateLiveActivity(phase: .repeating, level: 2, nextFire: at(300))))
    }

    @Test("A stale/duplicate fire of an already-reached rung is a no-op")
    func duplicateFireIsNoOp() {
        let st = MachineState(status: .active(level: 2), startAt: at(0), snoozeCount: 0)
        let (out, fx) = reduce(st, .levelFired(level: 1, source: .inferred), ctx(400))
        #expect(out == st)
        #expect(fx.isEmpty)
    }

    @Test("Last rung repeats advance the countdown but not the level")
    func lastRungRepeats() {
        let st = MachineState(status: .active(level: 2), startAt: at(0), snoozeCount: 0)
        let (out, fx) = reduce(st, .lastRungRepeated(index: 1, source: .observed), ctx(300))
        #expect(out.status == .active(level: 2))
        // From +300: firstLastFire +180, elapsed 120, next repeat = +180 + 2*120 = +420.
        #expect(fx.contains(.updateLiveActivity(phase: .repeating, level: 2, nextFire: at(420))))
    }

    // MARK: - Dismiss vs resolve

    @Test("Dismissing an alarm does NOT resolve; the ladder continues")
    func dismissDoesNotResolve() {
        let st = MachineState(status: .active(level: 1), startAt: at(0), snoozeCount: 0)
        let (out, fx) = reduce(st, .alarmDismissed(level: 1), ctx(120))
        #expect(out == st)                                  // state unchanged
        #expect(fx == [.append(LoggedEvent(kind: .alarmDismissed, level: 1, source: .userAction))])
    }

    // MARK: - Snooze & max-snooze escalation

    @Test("Snooze under the cap resumes at the same level")
    func snoozeHoldsUnderCap() {
        var st = MachineState(status: .active(level: 1), startAt: at(0), snoozeCount: 0)
        (st, _) = reduce(st, .userSnoozed(duration: 120), ctx(90))   // count -> 1
        let (out, fx) = reduce(st, .snoozeExpired, ctx(210))         // 1 !> cap(1)
        #expect(out.status == .active(level: 1))
        #expect(out.snoozeCount == 1)
        #expect(!fx.contains(.append(LoggedEvent(kind: .snoozeEscalated, level: 1, source: .system))))
    }

    @Test("Snooze over the cap escalates one rung and resets the snooze budget")
    func snoozeEscalatesOverCap() {
        // Pretend one snooze already happened at this level.
        var st = MachineState(status: .active(level: 1), startAt: at(0), snoozeCount: 1)
        (st, _) = reduce(st, .userSnoozed(duration: 120), ctx(240))  // count -> 2
        let (out, fx) = reduce(st, .snoozeExpired, ctx(360))         // 2 > cap(1)
        #expect(out.status == .active(level: 2))
        #expect(out.snoozeCount == 0)
        #expect(fx.contains(.append(LoggedEvent(kind: .snoozeEscalated, level: 2, source: .system))))
    }

    @Test("Escalation never runs past the last rung")
    func escalationClampsAtLastRung() {
        var st = MachineState(status: .active(level: 2), startAt: at(0), snoozeCount: 5)
        (st, _) = reduce(st, .userSnoozed(duration: 60), ctx(400))   // count -> 6, over cap
        let (out, _) = reduce(st, .snoozeExpired, ctx(500))
        #expect(out.status == .active(level: 2))                     // clamped at last (2)
    }

    // MARK: - Terminal transitions

    @Test("Done is terminal and swallows later events")
    func doneIsTerminal() {
        let st = MachineState(status: .active(level: 1), startAt: at(0), snoozeCount: 0)
        let (done, _) = reduce(st, .userMarkedDone, ctx(100))
        #expect(done.status == .done)
        let (after, fx) = reduce(done, .levelFired(level: 2, source: .observed), ctx(200))
        #expect(after.status == .done)
        #expect(fx.isEmpty)
    }

    @Test("Stop is terminal (record kept)")
    func stopIsTerminal() {
        let st = MachineState(status: .active(level: 1), startAt: at(0), snoozeCount: 0)
        let (out, fx) = reduce(st, .userStopped, ctx(100))
        #expect(out.status == .stopped)
        #expect(fx.contains(.append(LoggedEvent(kind: .userStopped, source: .userAction))))
        #expect(fx.contains(.endLiveActivity))
    }

    // MARK: - Replace (re-run a terminal Badger, D12)

    @Test("Replace re-runs a terminal Badger from a fresh start")
    func replaceReRunsFromTerminal() {
        let done = MachineState(status: .done, startAt: at(0), snoozeCount: 0)
        let (out, fx) = reduce(done, .replace(startAt: at(1000)), ctx(1000))
        #expect(out.status == .pending)
        #expect(out.startAt == at(1000))
        #expect(fx.contains(.append(LoggedEvent(kind: .replaced, source: .userAction))))
        #expect(fx.contains(.armSchedule(fromLevel: 0)))
    }

    @Test("Replace is a no-op on a non-terminal Badger")
    func replaceIgnoredWhenActive() {
        let active = MachineState(status: .active(level: 1), startAt: at(0), snoozeCount: 0)
        let (out, fx) = reduce(active, .replace(startAt: at(1000)), ctx(1000))
        #expect(out == active)
        #expect(fx.isEmpty)
    }

    // MARK: - Pure schedule math

    @Test("Repeat interval is the gap preceding the last rung; single-rung falls back to rung0 delay")
    func repeatIntervalMath() {
        #expect(repeatInterval(rungs: ladder) == 120)                       // 180 − 60
        #expect(repeatInterval(rungs: [Rung(index: 0, delay: 90)]) == 90)   // single-rung fallback
    }

    // MARK: - Reconciliation (catch-up while backgrounded)

    @Test("Reconcile infers missed rung fires and last-rung repeats, then lands at the last level")
    func reconcileInfersFiresAndRepeats() {
        // Backgrounded at active(0); reopened at +400.
        let st = MachineState(status: .active(level: 0), startAt: at(0), snoozeCount: 0)

        let events = catchUpEvents(for: st, ctx: ctx(400))
        #expect(events == [
            .levelFired(level: 1, source: .inferred),     // rung1 @ +60
            .levelFired(level: 2, source: .inferred),     // rung2 @ +180
            .lastRungRepeated(index: 1, source: .inferred),   // repeat @ +300 (next @ +420 > 400)
        ])

        let (out, fx) = reconcile(st, ctx(400))
        #expect(out.status == .active(level: 2))
        #expect(fx.last == .append(LoggedEvent(kind: .reconciled, source: .system)))
    }

    @Test("Reconcile fires SnoozeExpired when a snooze elapsed while backgrounded")
    func reconcileExpiresSnooze() {
        let st = MachineState(status: .snoozed(until: at(100), resumeLevel: 1), startAt: at(0), snoozeCount: 1)
        #expect(catchUpEvents(for: st, ctx: ctx(200)) == [.snoozeExpired])
        // Not yet due → nothing to catch up.
        #expect(catchUpEvents(for: st, ctx: ctx(50)).isEmpty)
    }

    @Test("Reconcile on a fresh pending Badger with nothing due yields no catch-up events")
    func reconcileNoOpWhenNothingDue() {
        let st = MachineState(status: .pending, startAt: at(1000), snoozeCount: 0)
        #expect(catchUpEvents(for: st, ctx: ctx(0)).isEmpty)   // starts in the future
    }
}
