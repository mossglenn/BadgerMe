//
//  EscalationPaletteTests.swift
//  BadgerKitTests — the pure escalation-tone decision (§16, M7 CP1). No SwiftUI, no channels:
//  value-in/value-out, the pattern of FocusFilterTests / AmbientPresentationTests. Behaviour is
//  pinned to match the widget's escalationTint so a later refactor onto this stays green.
//

import Testing
import Foundation
@testable import BadgerKit

@Suite("BadgerKit EscalationPalette (§16 colour decision)")
struct EscalationPaletteTests {

    private func tone(_ phase: BadgerActivityPhase, level: Int = 0, total: Int = 3,
                      stale: Bool = false) -> EscalationTone {
        EscalationPalette.tone(phase: phase, level: level, totalLevels: total, isStale: stale)
    }

    @Test("armed shows the Badger's identity tint")
    func armedIsIdentity() {
        #expect(tone(.armed) == .identity)
    }

    @Test("snoozed and terminal phases are muted")
    func snoozedAndTerminalAreMuted() {
        #expect(tone(.snoozed) == .muted)
        #expect(tone(.done) == .muted)
        #expect(tone(.stopped) == .muted)
    }

    @Test("the repeating tail is hot")
    func repeatingIsHot() {
        #expect(tone(.repeating) == .hot)
    }

    @Test("escalating ramps identity (cool half) → warm (upper half)")
    func escalatingRamps() {
        #expect(tone(.escalating, level: 0, total: 3) == .identity)  // 0/2 = 0.0
        #expect(tone(.escalating, level: 1, total: 3) == .warm)      // 1/2 = 0.5 (not < 0.5)
        #expect(tone(.escalating, level: 2, total: 3) == .warm)      // 2/2 = 1.0
    }

    @Test("a single-rung ladder stays at identity (no ramp)")
    func singleRungNoRamp() {
        #expect(tone(.escalating, level: 0, total: 1) == .identity)
        #expect(EscalationPalette.heat(level: 0, total: 1) == .identity)
    }

    @Test("a passed staleDate while escalating wins as overdue")
    func staleEscalatingIsOverdue() {
        #expect(tone(.escalating, level: 0, total: 3, stale: true) == .overdue)
        #expect(tone(.repeating, stale: true) == .overdue)   // repeating counts as escalating
        #expect(tone(.armed, stale: true) == .overdue)
    }

    @Test("stale does NOT override a non-escalating phase")
    func staleIgnoredWhenNotEscalating() {
        #expect(tone(.snoozed, stale: true) == .muted)
        #expect(tone(.done, stale: true) == .muted)
    }

    @Test("identity tint vocabulary includes the fallback and both widget resolvers' tokens")
    func identityTintsVocabulary() {
        let tints = EscalationPalette.identityTints
        #expect(tints.first == "accent")
        // Superset of the summary widget's smaller set.
        for t in ["red", "orange", "yellow", "green", "teal", "blue"] {
            #expect(tints.contains(t))
        }
        #expect(Set(tints).count == tints.count)   // no duplicates
    }
}
