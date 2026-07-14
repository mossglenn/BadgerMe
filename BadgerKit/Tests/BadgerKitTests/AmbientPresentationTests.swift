//
//  AmbientPresentationTests.swift
//  Pure phase→presentation rules extracted from the widget in code review #11.
//

import Testing
@testable import BadgerKit

@Suite("Ambient presentation rules")
struct AmbientPresentationTests {

    @Test("isEscalating is true for the live phases, false for snoozed/terminal")
    func isEscalating() {
        #expect(AmbientPresentation.isEscalating(.armed))
        #expect(AmbientPresentation.isEscalating(.escalating))
        #expect(AmbientPresentation.isEscalating(.repeating))
        #expect(AmbientPresentation.isEscalating(.overdue))
        #expect(!AmbientPresentation.isEscalating(.snoozed))
        #expect(!AmbientPresentation.isEscalating(.done))
        #expect(!AmbientPresentation.isEscalating(.stopped))
    }

    @Test("showsActions hides Done/Snooze only in terminal phases")
    func showsActions() {
        for p: BadgerActivityPhase in [.armed, .escalating, .repeating, .snoozed, .overdue] {
            #expect(AmbientPresentation.showsActions(p))
        }
        #expect(!AmbientPresentation.showsActions(.done))
        #expect(!AmbientPresentation.showsActions(.stopped))
    }

    @Test("statusLine reads the ladder position when escalating")
    func statusLineEscalating() {
        #expect(AmbientPresentation.statusLine(phase: .escalating, level: 1,
                                               totalLevels: 3, isStale: false) == "Level 2 of 3")
    }

    @Test("statusLine reports the last rung when repeating")
    func statusLineRepeating() {
        #expect(AmbientPresentation.statusLine(phase: .repeating, level: 2,
                                               totalLevels: 3, isStale: false) == "Repeating — level 3 of 3")
    }

    @Test("statusLine gives a fixed label for armed/snoozed/terminal phases")
    func statusLineFixedLabels() {
        #expect(AmbientPresentation.statusLine(phase: .armed, level: 0, totalLevels: 3, isStale: false) == "Armed")
        #expect(AmbientPresentation.statusLine(phase: .snoozed, level: 0, totalLevels: 3, isStale: false) == "Snoozed")
        #expect(AmbientPresentation.statusLine(phase: .done, level: 0, totalLevels: 3, isStale: false) == "Done")
        #expect(AmbientPresentation.statusLine(phase: .stopped, level: 0, totalLevels: 3, isStale: false) == "Stopped")
    }

    @Test("a stale escalating phase overrides the ladder text with the overdue message")
    func statusLineStaleOverride() {
        #expect(AmbientPresentation.statusLine(phase: .escalating, level: 1,
                                               totalLevels: 3, isStale: true) == "Overdue — escalating")
    }

    @Test("staleness does not override snoozed/terminal phases")
    func statusLineStaleIgnoredWhenNotEscalating() {
        #expect(AmbientPresentation.statusLine(phase: .snoozed, level: 0, totalLevels: 3, isStale: true) == "Snoozed")
        #expect(AmbientPresentation.statusLine(phase: .done, level: 0, totalLevels: 3, isStale: true) == "Done")
    }
}
