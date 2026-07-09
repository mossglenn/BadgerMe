//
//  ScheduleSlotCodableTests.swift
//  BadgerKitTests — locks the Codable contract for ScheduleSlot / ArmedRef
//  (M3 cold-kill fix, Checkpoint 1). The typed slot is what makes the persisted
//  armed record safe without a hand-written string encode/decode.
//

import Testing
import Foundation
@testable import BadgerKit

@Suite("ScheduleSlot / ArmedRef Codable")
struct ScheduleSlotCodableTests {

    private func roundTrip(_ slot: ScheduleSlot) throws -> ScheduleSlot {
        let data = try JSONEncoder().encode(slot)
        return try JSONDecoder().decode(ScheduleSlot.self, from: data)
    }

    @Test("all three ScheduleSlot cases round-trip identically")
    func slotRoundTrips() throws {
        #expect(try roundTrip(.rung(3)) == .rung(3))
        #expect(try roundTrip(.repeatTail(rung: 2, n: 7)) == .repeatTail(rung: 2, n: 7))
        #expect(try roundTrip(.wake) == .wake)
    }

    @Test("ArmedRef round-trips carrying its slot")
    func armedRefRoundTrips() throws {
        let ref = ArmedRef(id: "ABC-123", slot: .repeatTail(rung: 2, n: 5))
        let data = try JSONEncoder().encode(ref)
        let back = try JSONDecoder().decode(ArmedRef.self, from: data)
        #expect(back == ref)
    }
}
