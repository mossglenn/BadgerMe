//
//  EscalationPalette.swift
//  BadgerKit — the pure cool → warm → hot escalation colour DECISION (§16, M7 CP1).
//
//  The colour language is first-class (§16), not polish, so its decision lives in ONE
//  Foundation-only, tested place and every rendering surface (console, widget, Live Activity)
//  maps a `EscalationTone` → Color. This is behaviour-preserving with the widget's existing
//  `escalationTint`/`escalatingHeat` (BadgerMeWidgetLiveActivity.swift); a later checkpoint
//  refactors those call sites onto this. Keyed on `BadgerActivityPhase` (the pure phase enum in
//  AmbientPresentation.swift) so it needs no ActivityKit and unit-tests on macOS. Reducer untouched.
//

import Foundation

/// The semantic "heat" of a Badger's escalation. A tone is a decision, not a colour. Colour is a
/// PURE escalation-heat signal (P2 design pass): `.identity`/armed → the fixed calm sage floor,
/// `.warm` → amber, `.hot` → red, `.overdue` → orange, `.muted` → neutral. Per-Badger identity
/// now lives in the icon SHAPE, not colour (see `DesignTokens`, Design Brief A2).
public enum EscalationTone: Equatable, Sendable {
    case identity   // the Badger's own tint token — armed, and the cool half of the ramp
    case warm       // warming through the upper ladder
    case hot         // the repeating tail: hottest / most insistent
    case muted      // snoozed or terminal
    case overdue    // staleDate passed while still escalating
}

public enum EscalationPalette {
    /// Decide a Badger's tone from its ambient phase/level. Mirrors the widget's escalationTint:
    /// a passed staleDate while escalating wins as `.overdue`; snoozed/terminal are `.muted`; the
    /// repeating tail is `.hot`; `armed` shows identity; mid-ladder ramps identity → warm.
    public static func tone(phase: BadgerActivityPhase, level: Int, totalLevels: Int,
                            isStale: Bool) -> EscalationTone {
        if isStale, AmbientPresentation.isEscalating(phase) { return .overdue }
        switch phase {
        case .snoozed, .done, .stopped: return .muted
        case .repeating:                return .hot
        case .armed:                    return .identity
        case .escalating, .overdue:     return heat(level: level, total: totalLevels)
        }
    }

    /// Cool → warm ramp across the escalating rungs; a single-rung ladder stays at identity.
    /// Lower half of the ladder keeps the Badger's identity tint; the upper half warms.
    static func heat(level: Int, total: Int) -> EscalationTone {
        guard total > 1 else { return .identity }
        return Double(level) / Double(total - 1) < 0.5 ? .identity : .warm
    }

    /// Canonical identity tint vocabulary (§16): the tokens the create/edit picker offers and
    /// every surface's token → Color resolver understands. `accent` is the default/fallback and
    /// is a superset of both current widget resolvers, so they can unify onto this.
    public static let identityTints: [String] = [
        "accent", "red", "orange", "yellow", "green", "mint", "teal",
        "cyan", "blue", "indigo", "purple", "pink", "brown", "gray",
    ]
}
