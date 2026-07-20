//
//  LadderPresetsTests.swift
//  BadgerKitTests — the named D10 seed presets (§10/D10, M7 CP1). Pure value assertions; CP2
//  seeds these as LadderTemplates and points the create fallback at Default.
//

import Testing
import Foundation
@testable import BadgerKit

@Suite("BadgerKit LadderPresets (§10/D10 seed content)")
struct LadderPresetsTests {

    @Test("the trio is Gentle → Default → Urgent with stable, unique ids")
    func trio() {
        #expect(LadderPresets.all.map(\.name) == ["Gentle", "Default", "Urgent"])
        let ids = LadderPresets.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(LadderPresets.preset(id: LadderPresets.defaultID) == LadderPresets.balanced)
        #expect(LadderPresets.preset(id: UUID()) == nil)
    }

    @Test("every preset has ordered 0-based rungs with strictly increasing delays")
    func wellFormedRungs() {
        for p in LadderPresets.all {
            #expect(p.rungs.map(\.index) == Array(0..<p.rungs.count))
            #expect(zip(p.rungs, p.rungs.dropFirst()).allSatisfy { $0.delay < $1.delay })
            #expect(p.rungs.allSatisfy { !$0.actions.isEmpty })
            #expect(p.defaultMaxSnoozeCount >= 1)
        }
    }

    @Test("Gentle stays soft the whole way (no breakthrough), with the widest snooze budget")
    func gentleIsAllSoft() {
        let g = LadderPresets.gentle
        let proms = g.rungs.flatMap { $0.actions.map(\.prominence) }
        #expect(!proms.contains(.breakthrough))
        #expect(g.rungs.allSatisfy { $0.actions.allSatisfy { $0.channelID == "notification" } })
        #expect(g.defaultMaxSnoozeCount == 3)
    }

    @Test("Default and Urgent both end on a breakthrough AlarmKit last rung")
    func mixedLaddersEndBreakthrough() {
        for p in [LadderPresets.balanced, LadderPresets.urgent] {
            let last = p.rungs.last!
            #expect(last.actions.contains { $0.channelID == "alarmkit" && $0.prominence == .breakthrough })
        }
        // Urgent escalates hard sooner (by rung 1) and snoozes least.
        #expect(LadderPresets.urgent.rungs[1].actions.first?.prominence == .breakthrough)
        #expect(LadderPresets.urgent.defaultMaxSnoozeCount == 1)
    }

    @Test("presets draw sounds only from the built-in catalog")
    func soundsAreCatalogBacked() {
        for p in LadderPresets.all {
            for action in p.rungs.flatMap(\.actions) {
                guard case let .builtIn(id) = action.soundRef else {
                    Issue.record("preset \(p.name) used a non-builtIn sound")
                    continue
                }
                #expect(SoundCatalog.sound(id: id) != nil)
            }
        }
    }

    @Test("repeat interval is well-defined for every preset (last gap > 0)")
    func repeatIntervalDefined() {
        for p in LadderPresets.all {
            let rungs = p.rungs.map { Rung(index: $0.index, delay: $0.delay) }
            #expect(repeatInterval(rungs: rungs) > 0)
        }
    }
}
