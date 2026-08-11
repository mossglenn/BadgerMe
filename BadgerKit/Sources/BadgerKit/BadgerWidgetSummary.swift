//
//  BadgerWidgetSummary.swift
//  BadgerKit — read-only projection for the home/lock-screen widget (§11, M6 CP3).
//
//  The widget's TimelineProvider runs in the widget process, so it can't reach the in-app
//  engine (@Dependency). Instead it opens the shared App-Group ModelContainer read-only and
//  projects the non-terminal Badgers into this Sendable summary: an active count plus the
//  single most-urgent Badger (soonest next escalation), which the widget renders with a
//  fixed-target countdown + an inline Done. Next-fire is computed by the SAME pure
//  fireDate/nextFire the reducer/engine use, so the glance can't drift from the schedule.
//
//  Split: `nextEscalation` (per-Badger next fire) and `summarizeWidget` (pick soonest +
//  count) are pure/Foundation-only and unit-tested; `BadgerWidgetReader.summary` is the
//  thin I/O adapter that opens the store. Mirrors the pure-helper discipline of M3 #4 / CP1.
//

import Foundation
import SwiftData

/// A Sendable glance model of what's badgering the user, projected for the widget.
public struct BadgerWidgetSummary: Sendable, Equatable {
    /// Non-terminal Badgers (pending / active / snoozed) — matches `activeSnapshots()`.
    public let activeCount: Int
    /// The non-terminal Badger firing soonest (the inline-Done target); nil if none.
    public let mostUrgent: Item?

    public struct Item: Sendable, Equatable, Identifiable {
        public let id: UUID
        public let title: String
        public let tint: String
        public let iconName: String?
        public let nextFire: Date
        public let tone: EscalationTone
        public init(id: UUID, title: String, tint: String, iconName: String?, nextFire: Date,
                    tone: EscalationTone) {
            self.id = id; self.title = title; self.tint = tint
            self.iconName = iconName; self.nextFire = nextFire; self.tone = tone
        }
    }

    public init(activeCount: Int, mostUrgent: Item?) {
        self.activeCount = activeCount
        self.mostUrgent = mostUrgent
    }

    public static let empty = BadgerWidgetSummary(activeCount: 0, mostUrgent: nil)
}

/// The next escalation instant a Badger will fire, from its persisted fields and `now`:
/// pending → rung 0; snoozed → the resume time; active → the next rung or (at the last rung)
/// the next repeat; nil for terminal or an empty ladder. Pure — reuses the reducer's
/// fireDate/nextFire so the widget never diverges from the real schedule.
func nextEscalation(state: StoredBadgerState, startAt: Date, currentLevel: Int,
                    snoozeUntil: Date?, rungs: [Rung], now: Date) -> Date? {
    guard !rungs.isEmpty else { return nil }
    switch state {
    case .done, .stopped: return nil
    case .snoozed:        return snoozeUntil
    case .pending:        return fireDate(level: 0, startAt: startAt, rungs: rungs)
    case .active:
        let ctx = Context(now: now, rungs: rungs, maxSnoozeCount: 0)
        return nextFire(forLevel: min(currentLevel, rungs.count - 1), startAt: startAt, ctx: ctx)
    }
}

/// A Badger reduced to just what the widget summary needs. `nextFire` is nil for terminal
/// Badgers or an empty ladder.
struct WidgetBadgerInput: Equatable {
    let id: UUID
    let title: String
    let tint: String
    let iconName: String?
    let isTerminal: Bool
    let nextFire: Date?
    let tone: EscalationTone
}

/// Active count (non-terminal) + the non-terminal Badger firing soonest. Pure.
func summarizeWidget(_ inputs: [WidgetBadgerInput]) -> BadgerWidgetSummary {
    let live = inputs.filter { !$0.isTerminal }
    let urgent = live
        .compactMap { i in i.nextFire.map { (i, $0) } }
        .min { $0.1 < $1.1 }
        .map { BadgerWidgetSummary.Item(id: $0.0.id, title: $0.0.title, tint: $0.0.tint,
                                        iconName: $0.0.iconName, nextFire: $0.1, tone: $0.0.tone) }
    return BadgerWidgetSummary(activeCount: live.count, mostUrgent: urgent)
}

/// Opens the shared App-Group store read-only and projects the widget summary. Usable from
/// the widget process (no engine): it makes its own task-scoped `ModelContext` from the shared
/// container (§20 — never the app's @MainActor context). Best-effort — any failure yields
/// `.empty`, so a glance never blocks on I/O.
public enum BadgerWidgetReader {
    public static func summary(now: Date = Date()) -> BadgerWidgetSummary {
        guard let container = try? makeModelContainer(groupContainerID: BadgerConfig.appGroupID) else {
            return .empty
        }
        let context = ModelContext(container)
        let badgers = (try? context.fetch(FetchDescriptor<Badger>())) ?? []
        let inputs = badgers.map { b -> WidgetBadgerInput in
            let rungs = (b.ladder?.rungs ?? [])
                .sorted { $0.index < $1.index }
                .map { Rung(index: $0.index, delay: $0.delay) }
            let next = nextEscalation(state: b.state, startAt: b.startAt,
                                      currentLevel: b.currentLevel, snoozeUntil: b.snoozeUntil,
                                      rungs: rungs, now: now)
            return WidgetBadgerInput(id: b.id, title: b.title, tint: b.tint, iconName: b.iconName,
                                     isTerminal: b.state == .done || b.state == .stopped,
                                     nextFire: next,
                                     tone: EscalationPalette.tone(state: b.state, currentLevel: b.currentLevel, totalLevels: rungs.count))
        }
        return summarizeWidget(inputs)
    }
}
