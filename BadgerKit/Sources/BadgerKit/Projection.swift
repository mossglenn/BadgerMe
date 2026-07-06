//
//  Projection.swift
//  BadgerKit — the pure MachineState <-> Badger projection (Phase 5 §6/§7).
//
//  Connects the pure reducer state to the persisted Badger cache. No I/O: these are
//  the mapping decisions the engine uses when it loads a Badger into the reducer and
//  writes the reduced state + logged events back. The reducer file stays
//  Foundation-only; this file bridges it to the SwiftData models.
//

import Foundation

extension MachineState {
    /// Reconstruct the reducer's working state from a persisted Badger. The snoozed
    /// wake time comes from `snoozeUntil`, the resume level from `currentLevel`
    /// (equal while snoozed, §6 mapping). Terminal states carry no level.
    init(from badger: Badger) {
        let status: BadgerState
        switch badger.state {
        case .pending: status = .pending
        case .active:  status = .active(level: badger.currentLevel)
        case .snoozed: status = .snoozed(until: badger.snoozeUntil ?? badger.startAt,
                                         resumeLevel: badger.currentLevel)
        case .done:    status = .done
        case .stopped: status = .stopped
        }
        self.init(status: status, startAt: badger.startAt, snoozeCount: badger.snoozeCount)
    }
}

/// Write a reduced `MachineState` back onto a Badger's cache columns (§6) — the
/// inverse of `MachineState(from:)`. `resolvedAt` is stamped by the engine at the
/// transition time (this mapping carries no clock); `currentLevel` is left untouched
/// on terminal/pending transitions since those states don't carry a level.
func apply(_ state: MachineState, to badger: Badger) {
    badger.startAt = state.startAt
    badger.snoozeCount = state.snoozeCount
    switch state.status {
    case .pending:
        badger.state = .pending
        badger.snoozeUntil = nil
    case .active(let level):
        badger.state = .active
        badger.currentLevel = level
        badger.snoozeUntil = nil
    case .snoozed(let until, let resumeLevel):
        badger.state = .snoozed
        badger.currentLevel = resumeLevel
        badger.snoozeUntil = until
    case .done:
        badger.state = .done
        badger.snoozeUntil = nil
    case .stopped:
        badger.state = .stopped
        badger.snoozeUntil = nil
    }
}

/// Translate a reducer `LoggedEvent` (emitted as an `.append` effect) into a persisted
/// log row (§7). The engine assigns the monotonic `sequence` and the wall-clock time.
func makeEventRecord(from logged: LoggedEvent, badgerID: UUID,
                     sequence: Int, timestamp: Date) -> EventRecord {
    EventRecord(badgerID: badgerID, sequence: sequence, timestamp: timestamp,
                kind: logged.kind, level: logged.level, source: logged.source,
                detail: logged.detail)
}

/// Fold a scripted `(event, context)` stream through the reducer and return the
/// derived state (§18 replay / the B->C migration seam, §7). The reducer *is* the
/// fold logic; this makes replaying an event stream explicit.
func foldEvents(_ steps: [(event: Event, context: Context)],
                from seed: MachineState = .seed) -> MachineState {
    var state = seed
    for step in steps { state = reduce(state, step.event, step.context).0 }
    return state
}
