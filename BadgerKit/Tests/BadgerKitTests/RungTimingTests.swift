//
//  RungTimingTests.swift
//  BadgerKitTests — incremental→absolute delay conversion (D8, M7). Pure, Foundation-only.
//

import Testing
import Foundation
@testable import BadgerKit

@Suite("BadgerKit RungTiming — incremental → absolute (D8)")
struct RungTimingTests {

    private func spec(_ i: Int, _ d: TimeInterval) -> RungSpec {
        RungSpec(index: i, delay: d, actions: [])
    }

    @Test("accumulates incremental gaps into absolute-from-start delays")
    func accumulates() {
        let out = absoluteRungs(fromIncremental: [spec(0, 0), spec(1, 60), spec(2, 120)])
        #expect(out.map(\.delay) == [0, 60, 180])
        #expect(out.map(\.index) == [0, 1, 2])
    }

    @Test("sorts by index before accumulating")
    func sortsByIndexFirst() {
        let out = absoluteRungs(fromIncremental: [spec(2, 120), spec(0, 0), spec(1, 60)])
        #expect(out.map(\.delay) == [0, 60, 180])
    }

    @Test("single-rung ladder passes its gap through; empty stays empty")
    func edges() {
        #expect(absoluteRungs(fromIncremental: [spec(0, 90)]).map(\.delay) == [90])
        #expect(absoluteRungs(fromIncremental: []).isEmpty)
    }

    @Test("the last rung's incremental gap equals the reducer's repeat interval")
    func lastGapIsRepeatInterval() {
        // gaps [0,60,120] → absolute [0,60,180]; repeatInterval = 180-60 = 120 = last gap.
        let rungs = absoluteRungs(fromIncremental: [spec(0, 0), spec(1, 60), spec(2, 120)])
        #expect(repeatInterval(rungs: rungs) == 120)
    }
}
