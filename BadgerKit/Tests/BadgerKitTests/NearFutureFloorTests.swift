//
//  NearFutureFloorTests.swift
//  BadgerKitTests — the near-future scheduling clamp (§20 / B2). Pure, Foundation-only: the fix
//  for the on-device bug where an AlarmKit first rung at +0 (Start Now) never fired.
//

import Testing
import Foundation
@testable import BadgerKit

@Suite("BadgerKit NearFutureFloor (§20 near-future clamp)")
struct NearFutureFloorTests {

    private let t0 = Date(timeIntervalSinceReferenceDate: 0)

    @Test("clamps a past/now/too-soon fire date up to now + minLead; leaves a future date alone")
    func clampBehavior() {
        #expect(NearFutureFloor.clamp(t0.addingTimeInterval(-10), now: t0, minLead: 2) == t0.addingTimeInterval(2))
        #expect(NearFutureFloor.clamp(t0, now: t0, minLead: 2) == t0.addingTimeInterval(2))          // exactly now
        #expect(NearFutureFloor.clamp(t0.addingTimeInterval(1), now: t0, minLead: 2) == t0.addingTimeInterval(2))  // inside the lead
        #expect(NearFutureFloor.clamp(t0.addingTimeInterval(300), now: t0, minLead: 2) == t0.addingTimeInterval(300))  // comfortably future
    }

    @Test("floors are positive")
    func floorsPositive() {
        #expect(NearFutureFloor.notification > 0)
        #expect(NearFutureFloor.alarm > 0)
    }
}
