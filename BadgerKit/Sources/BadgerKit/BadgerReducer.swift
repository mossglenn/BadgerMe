//
//  BadgerReducer.swift
//  BadgerKit — reference implementation of the Phase 5 §8 state machine
//
//  This is the PURE CORE of BadgerMe: a deterministic reducer of the form
//      reduce(state, event, context) -> (newState, [effect])
//  with no I/O, no clock reads (time enters via `context.now`), and no beta
//  SDK dependencies. It mirrors the transition table in Phase 5 §8 exactly and
//  is the acceptance criteria for build-milestone M1: the domain is "done" when
//  the accompanying test suite is green.
//
//  It is also the fold-the-log logic for a future B->C migration (§7): the same
//  events and transitions apply whether state is stored (B) or replayed (C).
//
//  MAPPING TO PERSISTENCE (§6):
//    MachineState.status     <-> Badger.state          (raw-value-backed enum)
//    MachineState.snoozeCount <-> Badger.snoozeCount
//    MachineState.startAt    <-> Badger.startAt        (re-anchored on snooze/replace)
//    Effect.append(...)      -> a row appended to the Event log
//    Effect.armSchedule/...  -> the engine resolves ChannelActions -> AlertChannels
//  The engine (impure) executes effects and feeds observed/inferred events back in.
//
//  Whether the last-rung REPEAT is delivered as a recurring AlarmKit alarm
//  (breakthrough) or a replenished notification batch (soft) is an ENGINE concern
//  (§8/§10); the reducer only decides *when* the next fire is due.
//

import Foundation

// MARK: - Domain values

/// A single ladder step. `delay` is relative to start (Phase 5 §6 / D8).
/// The reducer needs only `index` and `delay`; the channel/prominence/sound of a
/// rung's actions live on `ChannelAction` in the full model and don't affect state.
struct Rung: Equatable {
    let index: Int
    /// Seconds from the Badger's start to this rung's fire time.
    let delay: TimeInterval
}

/// The Badger lifecycle state (Phase 5 §8). There is intentionally NO terminal
/// `exhausted` case in v1: exhaustion means "repeat the last rung forever until
/// resolved" — represented as `active(last)` with the `repeating` activity phase.
enum BadgerState: Equatable {
    case pending
    case active(level: Int)
    case snoozed(until: Date, resumeLevel: Int)
    case done
    case stopped

    var isTerminal: Bool { self == .done || self == .stopped }
}

/// The reducer's working state = the persisted lifecycle state plus the two pieces
/// of bookkeeping the transitions need.
struct MachineState: Equatable {
    var status: BadgerState
    /// Effective start used for fire-date math. Set by `created`; re-anchored to
    /// `now` on snooze-resume and `replace` so the remaining schedule is correct.
    var startAt: Date
    /// Snoozes at the current level; drives max-snooze escalation (D6). Reset when
    /// the ladder advances.
    var snoozeCount: Int

    /// A seed value for feeding the genesis `.created` event (its prior state is
    /// ignored). Not a valid persisted state on its own.
    static let seed = MachineState(status: .pending, startAt: .distantPast, snoozeCount: 0)
}

/// Static, frozen inputs for a single `reduce` call.
struct Context: Equatable {
    let now: Date
    /// The bound ladder's rungs, ordered by index; must be non-empty.
    let rungs: [Rung]
    /// Per-Badger snooze cap (seeded from the ladder). Snoozes beyond it escalate.
    let maxSnoozeCount: Int

    /// Highest rung index (the "last" rung, which repeats).
    var lastLevel: Int { rungs.count - 1 }
}

// MARK: - Events (inputs) and logged events (outputs)

enum EventSource: String, Equatable {
    case userAction   // the person acted (Done/Snooze/Stop/Dismiss/Replace/Edit)
    case observed     // observed live from AlarmKit/notification while running
    case inferred     // reconstructed during reconciliation
    case system       // engine-generated (armed, resumed, escalated, reconciled)
}

/// Events fed into the reducer. Reconciliation produces `inferred` `levelFired` /
/// `lastRungRepeated` / `snoozeExpired` events (see `catchUpEvents`).
enum Event: Equatable {
    case created(startAt: Date)
    case edited                                   // D2 OPEN — see note in reduce()
    case levelFired(level: Int, source: EventSource)
    case lastRungRepeated(index: Int, source: EventSource)   // nth repeat of the last rung
    case alarmDismissed(level: Int)               // AlarmKit "Stop" — does NOT resolve
    case userMarkedDone
    case userSnoozed(duration: TimeInterval)
    case snoozeExpired
    case userStopped
    case replace(startAt: Date)                   // re-run a terminal Badger (D12)
    case reopen(toLevel: Int)                     // undo a Done — reopen at the recorded level (CP5)
    case deleted
}

enum EventKind: String, Equatable {
    case created, edited, armed, levelFired, lastRungRepeated, alarmDismissed
    case notificationDelivered, userMarkedDone, userSnoozed, snoozeResumed
    case snoozeEscalated, userStopped, replaced, deleted, reconciled, reopened
}

/// A row destined for the append-only Event log (§7).
struct LoggedEvent: Equatable {
    let kind: EventKind
    var level: Int? = nil
    var detail: [String: String] = [:]
    let source: EventSource
}

// MARK: - Effects (executed by the impure engine)

enum Effect: Equatable {
    case append(LoggedEvent)
    /// Arm every rung >= `fromLevel` plus the last-rung repeat. Concrete fire dates
    /// are computed by the engine from `MachineState.startAt`; recurring-vs-batch is
    /// an engine choice based on the last rung's channel.
    case armSchedule(fromLevel: Int)
    case cancelAllPending
    case armWake(at: Date)
    case startLiveActivity(phase: BadgerActivityPhase, level: Int, nextFire: Date?)
    case updateLiveActivity(phase: BadgerActivityPhase, level: Int, nextFire: Date?)
    case endLiveActivity
}

// MARK: - Pure schedule math

/// Fire date of a base rung: start + its delay (delays are relative to start, D8).
func fireDate(level: Int, startAt: Date, rungs: [Rung]) -> Date {
    startAt.addingTimeInterval(rungs[level].delay)
}

/// Repeat interval for the last-rung repeat (D4): the gap that PRECEDED the last
/// rung's first fire — i.e. the delay between the penultimate and last rungs. For a
/// single-rung ladder it falls back to rung 0's delay-from-start.
func repeatInterval(rungs: [Rung]) -> TimeInterval {
    let last = rungs.count - 1
    if last >= 1 { return rungs[last].delay - rungs[last - 1].delay }
    return rungs[0].delay
}

/// The next time the last rung is due to (re)fire, strictly after `now`.
func nextRepeatDate(after now: Date, startAt: Date, rungs: [Rung]) -> Date {
    let last = rungs.count - 1
    let firstLastFire = fireDate(level: last, startAt: startAt, rungs: rungs)
    let interval = repeatInterval(rungs: rungs)
    guard interval > 0 else { return firstLastFire }
    if now < firstLastFire { return firstLastFire }         // last rung hasn't fired yet
    let elapsed = now.timeIntervalSince(firstLastFire)
    let k = floor(elapsed / interval) + 1                    // strictly-after
    return firstLastFire.addingTimeInterval(k * interval)
}

/// The next fire the ambient Live Activity should count down to, given the current
/// level. For a mid-ladder level it's the next rung; at the last rung it's the next
/// repeat. Always non-nil (the ladder never truly ends in v1).
func nextFire(forLevel level: Int, startAt: Date, ctx: Context) -> Date {
    if level < ctx.lastLevel {
        return fireDate(level: level + 1, startAt: startAt, rungs: ctx.rungs)
    }
    return nextRepeatDate(after: ctx.now, startAt: startAt, rungs: ctx.rungs)
}

/// The level to resume/snooze from. `pending` is treated as level 0 for this purpose.
private func currentLevel(_ status: BadgerState) -> Int {
    switch status {
    case .pending:                    return 0
    case .active(let l):              return l
    case .snoozed(_, let rl):         return rl
    case .done, .stopped:             return 0
    }
}

// MARK: - The reducer

/// Pure, deterministic. Mirrors the Phase 5 §8 transition table row-for-row.
func reduce(_ state: MachineState, _ event: Event, _ ctx: Context) -> (MachineState, [Effect]) {
    let last = ctx.lastLevel

    switch event {

    // Genesis. Prior state is ignored (the engine sends this exactly once).
    case .created(let startAt):
        let s = MachineState(status: .pending, startAt: startAt, snoozeCount: 0)
        let nf = fireDate(level: 0, startAt: startAt, rungs: ctx.rungs)
        return (s, [
            .append(LoggedEvent(kind: .created, source: .userAction)),
            .append(LoggedEvent(kind: .armed, source: .system)),
            .armSchedule(fromLevel: 0),
            .startLiveActivity(phase: .armed, level: 0, nextFire: nf),
        ])

    // A base rung reached its fire time (observed live or inferred on reconcile).
    // Monotonic: never regresses; duplicates of an already-reached rung are no-ops.
    case .levelFired(let level, let src):
        guard !state.status.isTerminal else { return (state, []) }
        switch state.status {
        case .snoozed:
            return (state, [])                       // canceled while snoozed; ignore stray fire
        case .pending:
            let newLevel = min(level, last)          // usually 0; collapses catch-up
            return advance(state, to: newLevel, ctx: ctx,
                           log: LoggedEvent(kind: .levelFired, level: newLevel, source: src))
        case .active(let k):
            guard level > k else { return (state, []) }   // stale/duplicate (repeats come separately)
            let newLevel = min(level, last)
            return advance(state, to: newLevel, ctx: ctx,
                           log: LoggedEvent(kind: .levelFired, level: newLevel, source: src))
        default:
            return (state, [])
        }

    // A repeat of the last rung (the v1 exhaustion behavior, D4). Stays at the last
    // level with the `repeating` phase; only meaningful once we're actually there.
    case .lastRungRepeated(let n, let src):
        guard case .active(let k) = state.status, k == last else { return (state, []) }
        let nf = nextRepeatDate(after: ctx.now, startAt: state.startAt, rungs: ctx.rungs)
        return (state, [
            .append(LoggedEvent(kind: .lastRungRepeated, level: last,
                                detail: ["repeat": String(n)], source: src)),
            .updateLiveActivity(phase: .repeating, level: last, nextFire: nf),
        ])

    // AlarmKit "Stop" silences one alert but does NOT resolve; the ladder continues.
    case .alarmDismissed(let level):
        guard !state.status.isTerminal else { return (state, []) }
        return (state, [.append(LoggedEvent(kind: .alarmDismissed, level: level, source: .userAction))])

    case .userMarkedDone:
        guard !state.status.isTerminal else { return (state, []) }
        var s = state; s.status = .done
        return (s, [
            .cancelAllPending,
            .append(LoggedEvent(kind: .userMarkedDone, source: .userAction)),
            .endLiveActivity,
        ])

    case .userSnoozed(let duration):
        guard !state.status.isTerminal else { return (state, []) }
        let rl = currentLevel(state.status)
        let until = ctx.now.addingTimeInterval(duration)
        var s = state
        s.status = .snoozed(until: until, resumeLevel: rl)
        s.snoozeCount += 1
        return (s, [
            .cancelAllPending,
            .append(LoggedEvent(kind: .userSnoozed,
                                detail: ["duration": String(Int(duration))], source: .userAction)),
            .armWake(at: until),
            .updateLiveActivity(phase: .snoozed, level: rl, nextFire: until),
        ])

    // Resume from snooze. Max-snooze escalation (D6): once snoozes exceed the cap,
    // advance one rung. NOTE (A vs B): advancing RESETS snoozeCount, so each level
    // gets a fresh snooze budget (spec §8 "advancing resets snoozeCount"). To make
    // every post-cap snooze escalate instead, drop the reset — a one-line change.
    case .snoozeExpired:
        guard case .snoozed(_, let rl) = state.status else { return (state, []) }
        let escalate = state.snoozeCount > ctx.maxSnoozeCount
        let resumeLevel = min(rl + (escalate ? 1 : 0), last)
        let advanced = resumeLevel > rl
        var s = state
        // Re-anchor so the resumed rung is "now" and the next rung fires after its
        // incremental delay: startAt' = now - rungs[resumeLevel].delay.
        s.startAt = ctx.now.addingTimeInterval(-ctx.rungs[resumeLevel].delay)
        s.status = .active(level: resumeLevel)
        if advanced { s.snoozeCount = 0 }
        var effects: [Effect] = [
            .append(LoggedEvent(kind: .snoozeResumed, level: resumeLevel, source: .system)),
        ]
        if advanced {
            effects.append(.append(LoggedEvent(kind: .snoozeEscalated, level: resumeLevel, source: .system)))
        }
        effects.append(.armSchedule(fromLevel: resumeLevel))
        let phase: BadgerActivityPhase = (resumeLevel == last) ? .repeating : .escalating
        effects.append(.updateLiveActivity(phase: phase, level: resumeLevel,
                                           nextFire: nextFire(forLevel: resumeLevel, startAt: s.startAt, ctx: ctx)))
        return (s, effects)

    case .userStopped:
        guard !state.status.isTerminal else { return (state, []) }
        var s = state; s.status = .stopped
        return (s, [
            .cancelAllPending,
            .append(LoggedEvent(kind: .userStopped, source: .userAction)),
            .endLiveActivity,
        ])

    // Re-run a terminal Badger from its bound ladder (D12). Only from done/stopped.
    case .replace(let startAt):
        guard state.status.isTerminal else { return (state, []) }
        let s = MachineState(status: .pending, startAt: startAt, snoozeCount: 0)
        let nf = fireDate(level: 0, startAt: startAt, rungs: ctx.rungs)
        return (s, [
            .append(LoggedEvent(kind: .replaced, source: .userAction)),
            .armSchedule(fromLevel: 0),
            .startLiveActivity(phase: .armed, level: 0, nextFire: nf),
        ])

    // Undo a completed Badger (CP5, §11): reverse UserMarkedDone. Only from `.done`
    // (Stop is a separate, non-undoable terminal). Restores `active(toLevel)`, re-anchors
    // `startAt` so the restored rung is "now" (mirroring snoozeExpired), re-arms from that
    // level, and STARTS a fresh ambient activity (the prior one ended on Done). The engine
    // supplies `toLevel` from the Badger's preserved `currentLevel`.
    case .reopen(let toLevel):
        guard case .done = state.status else { return (state, []) }
        let level = max(0, min(toLevel, last))
        var s = state
        s.startAt = ctx.now.addingTimeInterval(-ctx.rungs[level].delay)
        s.status = .active(level: level)
        s.snoozeCount = 0
        let phase: BadgerActivityPhase = (level == last) ? .repeating : .escalating
        return (s, [
            .append(LoggedEvent(kind: .reopened, level: level, source: .userAction)),
            .armSchedule(fromLevel: level),
            .startLiveActivity(phase: phase, level: level,
                               nextFire: nextFire(forLevel: level, startAt: s.startAt, ctx: ctx)),
        ])

    // D2 OPEN: this is the permissive "edit freely, cancel + re-arm from the current
    // level" baseline. The chosen edit policy (D2) may restrict edits while active;
    // when decided, tighten the guard here. Kept minimal on purpose.
    case .edited:
        guard !state.status.isTerminal else { return (state, []) }
        let k = currentLevel(state.status)
        let phase: BadgerActivityPhase
        if state.status == .pending { phase = .armed }
        else if k == last { phase = .repeating }
        else { phase = .escalating }
        return (state, [
            .cancelAllPending,
            .append(LoggedEvent(kind: .edited, source: .userAction)),
            .armSchedule(fromLevel: k),
            .updateLiveActivity(phase: phase, level: k,
                                nextFire: nextFire(forLevel: k, startAt: state.startAt, ctx: ctx)),
        ])

    // Deletion removes the entity; the state enum has no `deleted` case, so we emit
    // the teardown effects and leave `status` for the engine to discard.
    case .deleted:
        return (state, [
            .cancelAllPending,
            .append(LoggedEvent(kind: .deleted, source: .userAction)),
            .endLiveActivity,
        ])
    }
}

/// Advance to a strictly-higher level: reset the snooze budget, choose the phase
/// (repeating at the last rung), and refresh the ambient activity's countdown.
private func advance(_ state: MachineState, to newLevel: Int, ctx: Context,
                     log: LoggedEvent) -> (MachineState, [Effect]) {
    var s = state
    s.status = .active(level: newLevel)
    s.snoozeCount = 0
    let phase: BadgerActivityPhase = (newLevel == ctx.lastLevel) ? .repeating : .escalating
    let nf = nextFire(forLevel: newLevel, startAt: s.startAt, ctx: ctx)
    return (s, [
        .append(log),
        .updateLiveActivity(phase: phase, level: newLevel, nextFire: nf),
    ])
}

// MARK: - Reconciliation (pure)

/// Given the current state and `ctx.now`, produce the catch-up events that must have
/// occurred while the app was backgrounded (Phase 5 §14). These are fed back through
/// `reduce` — reconciliation is NOT a separate code path.
func catchUpEvents(for state: MachineState, ctx: Context) -> [Event] {
    let now = ctx.now, rungs = ctx.rungs, last = ctx.lastLevel

    switch state.status {
    case .snoozed(let until, _):
        return until <= now ? [.snoozeExpired] : []

    case .pending, .active:
        var events: [Event] = []
        let highestKnown: Int = { if case .active(let l) = state.status { return l } else { return -1 } }()

        // 1) Base rungs whose fire time has passed since the last known level.
        var level = highestKnown + 1
        while level <= last, fireDate(level: level, startAt: state.startAt, rungs: rungs) <= now {
            events.append(.levelFired(level: level, source: .inferred))
            level += 1
        }

        // 2) Last-rung repeats — only once the last rung has fired (known or inferred).
        let lastFired = highestKnown == last || events.contains {
            if case .levelFired(let l, _) = $0 { return l == last } else { return false }
        }
        if lastFired {
            let firstLastFire = fireDate(level: last, startAt: state.startAt, rungs: rungs)
            let interval = repeatInterval(rungs: rungs)
            if interval > 0, now > firstLastFire {
                let count = Int(floor(now.timeIntervalSince(firstLastFire) / interval))
                if count >= 1 {
                    for n in 1...count { events.append(.lastRungRepeated(index: n, source: .inferred)) }
                }
            }
        }
        return events

    default:
        return []
    }
}

/// Fold the catch-up events through the reducer and append a `reconciled` marker.
/// Convenience wrapper the engine uses on `AppActivated`.
func reconcile(_ state: MachineState, _ ctx: Context) -> (MachineState, [Effect]) {
    var s = state
    var effects: [Effect] = []
    for ev in catchUpEvents(for: s, ctx: ctx) {
        let (ns, fx) = reduce(s, ev, ctx)
        s = ns
        effects.append(contentsOf: fx)
    }
    effects.append(.append(LoggedEvent(kind: .reconciled, source: .system)))
    return (s, effects)
}
