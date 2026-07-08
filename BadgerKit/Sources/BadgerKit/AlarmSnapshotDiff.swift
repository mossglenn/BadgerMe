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
        events.append(.dismissed(badgerID: owner.badgerID, rung: rungIndex(owner.slot)))
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
        return .levelFired(badgerID: badgerID, rung: -1)
    }
}

private func rungIndex(_ slot: ScheduleSlot) -> Int {
    switch slot {
    case .rung(let k):             return k
    case .repeatTail(let rung, _): return rung
    case .wake:                    return -1
    }
}
