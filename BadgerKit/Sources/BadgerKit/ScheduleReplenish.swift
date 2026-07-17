//
//  ScheduleReplenish.swift
//  BadgerKit — pure "what should be armed now" for reconcile replenishment (§14, M6 CP1).
//
//  The last-rung repeat is a bounded batch of one-shot alerts (SP3: no v1 channel recurs),
//  so a Badger left repeating in the background eventually exhausts the batch and goes
//  silent. On reconcile the engine's `ensureArmed(...)` diffs the desired forward slots
//  below against what's actually armed and fills the gaps — re-topping the batch and
//  re-asserting future rungs. This decision is pure/Foundation-only so it unit-tests
//  without channels, the pattern established by `AlarmSnapshotDiff` (M3 review #4).
//
//  Scope note (CP1): detecting an AlarmKit alarm the system *dropped* (e.g. across a
//  device restart) while its ref still sits in `armedAlarms` needs the app-global system
//  enumeration that M6 CP2 (the stray sweep) introduces — so full "re-arm what the OS
//  lost" for the breakthrough channel rides on CP2. CP1 covers batch replenishment (new
//  future occurrences are genuinely un-armed, no ambiguity) and idempotent re-assertion
//  of notification slots (deterministic identifiers → `add` replaces).
//

import Foundation

/// The forward-looking ladder slots a non-terminal Badger SHOULD have armed at `ctx.now`:
/// every base rung above the highest reached whose fire time is still in the future, plus
/// — once the last rung is active (the `repeating` phase) — the next `repeatBatchSize`
/// repeat-tail occurrences. Deterministic and clock-driven via `ctx.now`; no I/O. Terminal
/// and snoozed Badgers arm nothing here (a snooze wake is armed separately).
func forwardSlots(state: MachineState, ctx: Context, repeatBatchSize: Int) -> [ScheduleSlot] {
    guard !state.status.isTerminal else { return [] }
    let last = ctx.lastLevel
    let now = ctx.now
    var slots: [ScheduleSlot] = []

    let reached: Int                 // highest rung already fired (-1 if none yet)
    switch state.status {
    case .pending:        reached = -1
    case .active(let k):  reached = k
    case .snoozed:        return []   // paused; the wake is armed via armWake, not here
    case .done, .stopped: return []
    }

    // Future base rungs above the highest reached (past/reached rungs aren't re-armed).
    var k = reached + 1
    while k <= last {
        if fireDate(level: k, startAt: state.startAt, rungs: ctx.rungs) > now {
            slots.append(.rung(k))
        }
        k += 1
    }

    // Repeat tail: only once we're actually at the last rung (repeating).
    if case .active(let level) = state.status, level == last {
        let interval = repeatInterval(rungs: ctx.rungs)
        if interval > 0 {
            let firstLastFire = fireDate(level: last, startAt: state.startAt, rungs: ctx.rungs)
            let firstFuture = max(1, Int(floor(now.timeIntervalSince(firstLastFire) / interval)) + 1)
            for n in firstFuture ..< (firstFuture + repeatBatchSize) {
                slots.append(.repeatTail(rung: last, n: n))
            }
        }
    }
    return slots
}
