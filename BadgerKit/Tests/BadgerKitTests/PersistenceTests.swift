//
//  PersistenceTests.swift
//  BadgerKitTests — §6 model + §18 schema/round-trip acceptance.
//
//  Opens an in-memory container against BadgerSchemaV1 (exercising the migration
//  plan's no-op path) and asserts a Badger + its frozen ladder + events round-trip.
//

import Testing
import Foundation
import SwiftData
@testable import BadgerKit

@Suite("BadgerKit persistence (Phase 5 §6/§7)")
@MainActor
struct PersistenceTests {

    private func container() throws -> ModelContainer {
        try makeModelContainer(inMemory: true)
    }

    @Test("Container opens against the versioned schema + no-op migration plan")
    func containerOpens() throws {
        _ = try container()
    }

    @Test("A Badger with a frozen ladder round-trips")
    func badgerRoundTrips() throws {
        let ctx = ModelContext(try container())
        let ladder = BoundLadder(rungs: [
            RungSpec(index: 0, delay: 0, actions: [
                ChannelAction(channelID: "alarmkit", prominence: .breakthrough,
                              soundRef: .builtIn(id: "badger")),
            ]),
            RungSpec(index: 1, delay: 60, actions: [
                ChannelAction(channelID: "notification", prominence: .timeSensitive,
                              soundRef: .imported(filename: "klaxon.caf")),
            ]),
        ])
        let badger = Badger(title: "Take meds",
                            startAt: Date(timeIntervalSinceReferenceDate: 0),
                            source: .manual, maxSnoozeCount: 1, ladder: ladder)
        ctx.insert(badger)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<Badger>())
        #expect(fetched.count == 1)
        let b = try #require(fetched.first)
        #expect(b.title == "Take meds")
        #expect(b.state == .pending)
        #expect(b.source == .manual)
        #expect(b.ladder?.rungs.count == 2)
        #expect(b.ladder?.rungs.first?.actions.first?.prominence == .breakthrough)
        #expect(b.ladder?.rungs.first?.actions.first?.soundRef == .builtIn(id: "badger"))
        #expect(b.ladder?.rungs.last?.delay == 60)
    }

    @Test("Raw-value enum columns persist and read back through their accessors")
    func enumColumnsRoundTrip() throws {
        let ctx = ModelContext(try container())
        let b = Badger(title: "x", startAt: .now, source: .appleReminders,
                       state: .snoozed, maxSnoozeCount: 2)
        b.snoozeUntil = Date(timeIntervalSinceReferenceDate: 500)
        b.armedAlarmIDs = [2: UUID()]
        ctx.insert(b)
        try ctx.save()

        let got = try #require(try ctx.fetch(FetchDescriptor<Badger>()).first)
        #expect(got.state == .snoozed)
        #expect(got.stateRaw == "snoozed")
        #expect(got.source == .appleReminders)
        #expect(got.snoozeUntil == Date(timeIntervalSinceReferenceDate: 500))
        #expect(got.armedAlarmIDs.keys.contains(2))
    }

    @Test("Event log rows persist and query by badgerID")
    func eventLogRoundTrips() throws {
        let ctx = ModelContext(try container())
        let bid = UUID()
        ctx.insert(EventRecord(badgerID: bid, sequence: 0, kind: .created, source: .userAction))
        ctx.insert(EventRecord(badgerID: bid, sequence: 1, kind: .levelFired, level: 0, source: .observed))
        try ctx.save()

        let all = try ctx.fetch(FetchDescriptor<EventRecord>(sortBy: [SortDescriptor(\.sequence)]))
        #expect(all.count == 2)
        #expect(all.first?.kind == .created)
        #expect(all.last?.kind == .levelFired)
        #expect(all.last?.level == 0)
        #expect(all.last?.source == .observed)
    }
}
