//
//  AlarmSnapshotDiffTests.swift
//  BadgerKitTests — AlarmKit snapshot diffing behavior.
//

import Testing
import Foundation
@testable import BadgerKit

@Suite("Alarm snapshot diffing")
struct AlarmSnapshotDiffTests {

    @Test("first alerting transition fires once, duplicate snapshots do not refire")
    func firstAlertingOnlyOnce() {
        let id = UUID()
        let badgerID = UUID()
        let owners = [id: (badgerID: badgerID, slot: ScheduleSlot.rung(2))]
        let first = diffAlarmSnapshot(
            entries: [AlarmSnapshotEntry(id: id, isAlerting: true)],
            owners: owners,
            lastAlerting: [:]
        )
        #expect(first.events == [.levelFired(badgerID: badgerID, rung: 2)])
        let second = diffAlarmSnapshot(
            entries: [AlarmSnapshotEntry(id: id, isAlerting: true)],
            owners: owners,
            lastAlerting: first.newLastAlerting
        )
        #expect(second.events.isEmpty)
    }

    @Test("disappearance emits dismissal and owner cleanup ids")
    func disappearanceDismisses() {
        let id = UUID()
        let badgerID = UUID()
        let owners = [id: (badgerID: badgerID, slot: ScheduleSlot.rung(1))]
        let diff = diffAlarmSnapshot(entries: [], owners: owners, lastAlerting: [id: false])
        #expect(diff.events == [.dismissed(badgerID: badgerID, rung: 1)])
        #expect(diff.removedOwners == [id])
    }

    @Test("unowned alarms are ignored")
    func unownedIgnored() {
        let diff = diffAlarmSnapshot(
            entries: [AlarmSnapshotEntry(id: UUID(), isAlerting: true)],
            owners: [:],
            lastAlerting: [:]
        )
        #expect(diff.events.isEmpty)
        #expect(diff.removedOwners.isEmpty)
    }

    @Test("repeat-tail alerting emits repeatFired")
    func repeatTailEvent() {
        let id = UUID()
        let badgerID = UUID()
        let owners = [id: (badgerID: badgerID, slot: ScheduleSlot.repeatTail(rung: 3, n: 4))]
        let diff = diffAlarmSnapshot(
            entries: [AlarmSnapshotEntry(id: id, isAlerting: true)],
            owners: owners,
            lastAlerting: [:]
        )
        #expect(diff.events == [.repeatFired(badgerID: badgerID, rung: 3, n: 4)])
    }

    @Test("a wake alarm produces no channel event, alerting or disappearing")
    func wakeEmitsNothing() {
        let id = UUID()
        let badgerID = UUID()
        let owners = [id: (badgerID: badgerID, slot: ScheduleSlot.wake)]
        let fired = diffAlarmSnapshot(
            entries: [AlarmSnapshotEntry(id: id, isAlerting: true)],
            owners: owners,
            lastAlerting: [:]
        )
        #expect(fired.events.isEmpty)
        let gone = diffAlarmSnapshot(entries: [], owners: owners, lastAlerting: [id: false])
        #expect(gone.events.isEmpty)
        #expect(gone.removedOwners == [id])
    }
}
