//
//  BadgerWidgetSummaryTests.swift
//  BadgerKitTests — pure projection for the home/lock-screen widget (§11, M6 CP3).
//
//  Covers next-escalation computation (reused from the reducer's fireDate/nextFire) and the
//  pick-soonest/count summary, so the widget's TimelineProvider stays a thin store reader.
//

import Testing
import Foundation
@testable import BadgerKit

@Suite("BadgerKit widget summary — pure projection (§11, M6 CP3)")
struct BadgerWidgetSummaryTests {

    private let T0 = Date(timeIntervalSinceReferenceDate: 0)
    private func at(_ s: TimeInterval) -> Date { T0.addingTimeInterval(s) }

    // rung0 @ +0, rung1 @ +60, rung2 @ +180 (last). Repeat interval = 120.
    private let rungs = [Rung(index: 0, delay: 0), Rung(index: 1, delay: 60), Rung(index: 2, delay: 180)]

    // MARK: - nextEscalation

    @Test("pending → rung 0's fire")
    func pendingNextIsRung0() {
        #expect(nextEscalation(state: .pending, startAt: at(0), currentLevel: 0,
                               snoozeUntil: nil, rungs: rungs, now: at(0)) == at(0))
    }

    @Test("active mid-ladder → the next rung")
    func activeNextIsNextRung() {
        #expect(nextEscalation(state: .active, startAt: at(0), currentLevel: 0,
                               snoozeUntil: nil, rungs: rungs, now: at(10)) == at(60))
        #expect(nextEscalation(state: .active, startAt: at(0), currentLevel: 1,
                               snoozeUntil: nil, rungs: rungs, now: at(70)) == at(180))
    }

    @Test("active at the last rung → the next repeat")
    func activeLastIsNextRepeat() {
        // firstLastFire +180, interval 120; from +180 the next strictly-after repeat is +300.
        #expect(nextEscalation(state: .active, startAt: at(0), currentLevel: 2,
                               snoozeUntil: nil, rungs: rungs, now: at(180)) == at(300))
    }

    @Test("snoozed → the resume time")
    func snoozedNextIsResume() {
        #expect(nextEscalation(state: .snoozed, startAt: at(0), currentLevel: 1,
                               snoozeUntil: at(500), rungs: rungs, now: at(200)) == at(500))
    }

    @Test("terminal or empty ladder → nil")
    func terminalOrEmptyIsNil() {
        #expect(nextEscalation(state: .done, startAt: at(0), currentLevel: 2,
                               snoozeUntil: nil, rungs: rungs, now: at(0)) == nil)
        #expect(nextEscalation(state: .stopped, startAt: at(0), currentLevel: 0,
                               snoozeUntil: nil, rungs: rungs, now: at(0)) == nil)
        #expect(nextEscalation(state: .pending, startAt: at(0), currentLevel: 0,
                               snoozeUntil: nil, rungs: [], now: at(0)) == nil)
    }

    // MARK: - summarizeWidget

    private func input(_ id: UUID, terminal: Bool, fire: Date?) -> WidgetBadgerInput {
        WidgetBadgerInput(id: id, title: id.uuidString, tint: "accent",
                          iconName: nil, isTerminal: terminal, nextFire: fire, tone: .identity)
    }

    @Test("count is non-terminal only; most-urgent is the soonest fire")
    func summaryPicksSoonest() {
        let a = UUID(), b = UUID(), c = UUID(), done = UUID()
        let s = summarizeWidget([
            input(a, terminal: false, fire: at(300)),
            input(b, terminal: false, fire: at(120)),   // soonest
            input(c, terminal: false, fire: at(500)),
            input(done, terminal: true, fire: nil),
        ])
        #expect(s.activeCount == 3)
        #expect(s.mostUrgent?.id == b)
        #expect(s.mostUrgent?.nextFire == at(120))
    }

    @Test("no non-terminal Badgers → empty summary")
    func summaryEmptyWhenAllTerminal() {
        let s = summarizeWidget([input(UUID(), terminal: true, fire: nil)])
        #expect(s == .empty)
    }

    @Test("non-terminal Badgers with no scheduled fire still count but yield no most-urgent")
    func summaryCountsWithoutFire() {
        let s = summarizeWidget([input(UUID(), terminal: false, fire: nil),
                                 input(UUID(), terminal: false, fire: nil)])
        #expect(s.activeCount == 2)
        #expect(s.mostUrgent == nil)
    }
}
