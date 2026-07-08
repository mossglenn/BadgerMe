//
//  AlarmSnapshotDiff.swift
//  BadgerKit — AlarmKit-free snapshot diffing for observed channel transitions.
//

import Foundation

struct AlarmSnapshotEntry: Equatable {
    let id: UUID
    let isAlerting: Bool
}

func diffAlarmSnapshot(
    entries: [AlarmSnapshotEntry],
    owners: [UUID: (badgerID: UUID, slot: ScheduleSlot)],
    lastAlerting: [UUID: Bool]
) -> (events: [ChannelEvent], newLastAlerting: [UUID: Bool], removedOwners: [UUID]) {
    var events: [ChannelEvent] = []
    var nextLastAlerting = lastAlerting
    var removedOwners: [UUID] = []
    let presentIDs = Set(entries.map(\.id))

    for entry in entries {
        guard let owner = owners[entry.id] else { continue }
        let priorAlerting = lastAlerting[entry.id] ?? false
        if entry.isAlerting, !priorAlerting {
            if let event = firedEvent(badgerID: owner.badgerID, slot: owner.slot) {
                events.append(event)
            }
        }
        nextLastAlerting[entry.id] = entry.isAlerting
    }

    for (alarmID, owner) in owners where !presentIDs.contains(alarmID) {
        if let event = dismissedEvent(badgerID: owner.badgerID, slot: owner.slot) {
            events.append(event)
        }
        nextLastAlerting[alarmID] = nil
        removedOwners.append(alarmID)
    }

    return (events, nextLastAlerting, removedOwners)
}

private func firedEvent(badgerID: UUID, slot: ScheduleSlot) -> ChannelEvent? {
    switch slot {
    case .rung(let k):
        return .levelFired(badgerID: badgerID, rung: k)
    case .repeatTail(let rung, let n):
        return .repeatFired(badgerID: badgerID, rung: rung, n: n)
    case .wake:
        // A wake alarm is a snooze-expiry nudge, not a rung fire; SnoozeExpired is
        // reconcile-driven (§14). Emit no channel event. Unreachable today (armWake is
        // notification-only), but guards the §8-open path of an AlarmKit-backed wake.
        return nil
    }
}

private func dismissedEvent(badgerID: UUID, slot: ScheduleSlot) -> ChannelEvent? {
    switch slot {
    case .rung(let k):             return .dismissed(badgerID: badgerID, rung: k)
    case .repeatTail(let rung, _): return .dismissed(badgerID: badgerID, rung: rung)
    case .wake:                    return nil
    }
}
