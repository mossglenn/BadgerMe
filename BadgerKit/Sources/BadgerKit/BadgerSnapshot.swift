//
//  BadgerSnapshot.swift
//  BadgerKit — a Sendable value projection of a Badger for the App Intents read side (M4).
//
//  BadgerEntity / the entity queries run off the main actor and reach the @MainActor
//  engine via `await engine.…`; handing back a SwiftData `@Model Badger` across that
//  boundary would violate Swift 6 strict concurrency (Badger is not Sendable). The
//  engine therefore projects each Badger into this immutable value on the main actor
//  and returns it. It carries exactly what BadgerEntity needs for its
//  DisplayRepresentation (title + status subtitle + icon) and what the queries filter
//  on (state, name); richer fields are added when a surface needs them.
//

import Foundation

/// An immutable, Sendable read model of a Badger, projected by the engine (§11/§6).
public struct BadgerSnapshot: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let title: String
    public let notes: String?
    public let state: StoredBadgerState
    /// Highest fired rung (cache). Meaningful for `.active`; 0 for `.pending`.
    public let currentLevel: Int
    /// Total rungs in the bound ladder (for a "level k of n" subtitle).
    public let totalLevels: Int
    public let iconName: String?
    public let tint: String

    public init(id: UUID, title: String, notes: String?, state: StoredBadgerState,
                currentLevel: Int, totalLevels: Int, iconName: String?, tint: String) {
        self.id = id
        self.title = title
        self.notes = notes
        self.state = state
        self.currentLevel = currentLevel
        self.totalLevels = totalLevels
        self.iconName = iconName
        self.tint = tint
    }

    /// True for `.done` / `.stopped` — the terminal states Replace re-runs from (D12).
    public var isTerminal: Bool { state == .done || state == .stopped }

    /// A short, user-facing status line for the entity subtitle (§11).
    public var statusSubtitle: String {
        switch state {
        case .pending: return "Pending"
        case .active:  return totalLevels > 1 ? "Escalating — level \(currentLevel + 1) of \(totalLevels)"
                                              : "Escalating"
        case .snoozed: return "Snoozed"
        case .done:    return "Done"
        case .stopped: return "Stopped"
        }
    }
}
