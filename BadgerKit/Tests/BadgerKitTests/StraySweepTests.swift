//
//  StraySweepTests.swift
//  BadgerKitTests — pure identifier diffs for the CP2 backstop stray sweep (§14 Part B).
//
//  Covers the two pure diffs and the notification-identifier parser they lean on, so the
//  engine's `sweepStrayAlerts()` stays a thin adapter (the pure-helper discipline of M3 #4).
//

import Testing
import Foundation
@testable import BadgerKit

@Suite("BadgerKit stray sweep — pure identifier diffs (§14 Part B, M6 CP2)")
struct StraySweepTests {

    // MARK: - strayIdentifiers (AlarmKit: opaque-UUID set difference)

    @Test("system ids not owned are stray; owned are kept, order preserved")
    func alarmDiffBasic() {
        let a = UUID().uuidString, b = UUID().uuidString, orphan = UUID().uuidString
        #expect(strayIdentifiers(system: [a, orphan, b], owned: [a, b]) == [orphan])
    }

    @Test("empty owned set (all Badgers terminal) sweeps every system id")
    func alarmDiffAllTerminal() {
        let a = UUID().uuidString, b = UUID().uuidString
        #expect(strayIdentifiers(system: [a, b], owned: []) == [a, b])
    }

    @Test("empty system set is a no-op")
    func alarmDiffEmptySystem() {
        #expect(strayIdentifiers(system: [], owned: [UUID().uuidString]).isEmpty)
    }

    @Test("an owned ref absent from the system set is simply not returned (OS-dropped ref is harmless)")
    func alarmDiffDroppedRef() {
        let live = UUID().uuidString, dropped = UUID().uuidString
        #expect(strayIdentifiers(system: [live], owned: [live, dropped]) == [])
    }

    // MARK: - badgerID(fromIdentifier:) — inverse of identifier(badgerID:slot:)

    @Test("parses the owning Badger id from every slot's identifier")
    func parseIdentifier() {
        let id = UUID()
        for slot: ScheduleSlot in [.rung(0), .rung(7), .repeatTail(rung: 2, n: 5), .wake] {
            let s = BadgerNotifications.identifier(badgerID: id, slot: slot)
            #expect(BadgerNotifications.badgerID(fromIdentifier: s) == id)
        }
    }

    @Test("a foreign / malformed identifier parses to nil")
    func parseForeign() {
        #expect(BadgerNotifications.badgerID(fromIdentifier: "com.other.app-thing") == nil)
        #expect(BadgerNotifications.badgerID(fromIdentifier: "badger-not-a-uuid-rung-0") == nil)
        #expect(BadgerNotifications.badgerID(fromIdentifier: "") == nil)
    }

    // MARK: - strayNotificationIdentifiers (namespace attribution)

    @Test("pending notifications of a dead Badger are stray; a live Badger's are kept")
    func notifDiff() {
        let live = UUID(), dead = UUID()
        let system = [
            BadgerNotifications.identifier(badgerID: live, slot: .rung(0)),
            BadgerNotifications.identifier(badgerID: live, slot: .rung(1)),
            BadgerNotifications.identifier(badgerID: dead, slot: .rung(0)),
            BadgerNotifications.identifier(badgerID: dead, slot: .repeatTail(rung: 1, n: 2)),
        ]
        let strays = strayNotificationIdentifiers(system: system, liveBadgerIDs: [live])
        #expect(Set(strays) == [
            BadgerNotifications.identifier(badgerID: dead, slot: .rung(0)),
            BadgerNotifications.identifier(badgerID: dead, slot: .repeatTail(rung: 1, n: 2)),
        ])
    }

    @Test("a foreign pending id is left alone (never swept)")
    func notifDiffLeavesForeign() {
        let dead = UUID()
        let system = ["com.other.reminder-42",
                      BadgerNotifications.identifier(badgerID: dead, slot: .wake)]
        #expect(strayNotificationIdentifiers(system: system, liveBadgerIDs: [])
                == [BadgerNotifications.identifier(badgerID: dead, slot: .wake)])
    }

    @Test("no live Badgers sweeps all our pending ids but still spares foreign ones")
    func notifDiffAllDead() {
        let a = UUID(), b = UUID()
        let system = [BadgerNotifications.identifier(badgerID: a, slot: .rung(0)),
                      BadgerNotifications.identifier(badgerID: b, slot: .rung(0)),
                      "system-thing"]
        let strays = strayNotificationIdentifiers(system: system, liveBadgerIDs: [])
        #expect(Set(strays) == [BadgerNotifications.identifier(badgerID: a, slot: .rung(0)),
                                BadgerNotifications.identifier(badgerID: b, slot: .rung(0))])
    }
}
