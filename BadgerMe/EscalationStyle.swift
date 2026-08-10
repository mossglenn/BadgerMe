//
//  EscalationStyle.swift
//  BadgerMe — the console's phase derivation over BadgerKit's escalation palette (§16).
//
//  The palette DECIDES a tone and BadgerKit maps tone → Color (EscalationPalette+Color, shared with
//  the widget/Live Activity — CP6). This file only adds the console-specific bit: deriving an
//  ambient phase from a persisted Badger's stored state (the console has no live LA phase). Colour
//  is always paired with a text/symbol status in the views (never colour-only) for accessibility.
//

import SwiftUI
import SwiftData
import BadgerKit

enum EscalationStyle {
    /// Derive the ambient phase from a persisted Badger's state (the console has no live LA phase).
    /// `active` at the last rung is the repeating tail. `isStale` is false in the console (live view).
    static func phase(state: StoredBadgerState, currentLevel: Int, totalLevels: Int) -> BadgerActivityPhase {
        EscalationPalette.phase(state: state, currentLevel: currentLevel, totalLevels: totalLevels)
    }
}

extension Badger {
    /// True while the model is still attached to a context. After delete + save a SwiftUI view can
    /// briefly still hold the object; touching a relationship (`ladder.rungs`) on a detached model
    /// traps ("backing data was detached… without resolving attribute faults"), so guard on this.
    var isLive: Bool { modelContext != nil }

    /// Total rungs in the bound ladder (min 1 for the repeat-interval fallback).
    var totalLevels: Int {
        guard isLive else { return 1 }
        return max(1, ladder?.rungs.count ?? 1)
    }

    /// This Badger's live escalation tone, via the pure palette.
    var escalationTone: EscalationTone {
        guard isLive else { return .muted }
        return EscalationPalette.tone(
            phase: EscalationStyle.phase(state: state, currentLevel: currentLevel, totalLevels: totalLevels),
            level: currentLevel, totalLevels: totalLevels, isStale: false)
    }

    /// The colour for this Badger's status indicator (paired with text/symbol in the UI).
    var escalationColor: Color { escalationTone.color(tint: tint) }

    /// The identity glyph (SHAPE = which Badger; colour = heat, applied separately). Falls back
    /// to a paw until the per-Badger icon picker ships (deferred, P2).
    var identityImage: Image {
        if let iconName { return Image(systemName: iconName) }
        return Image("badgerpaw.fill")
    }

    var isTerminal: Bool { state == .done || state == .stopped }

    /// A short, user-facing status line, shared by the list row and the detail header.
    var statusText: String {
        guard isLive else { return "" }
        switch state {
        case .pending: return "Pending"
        case .active:
            return totalLevels > 1
                ? "Escalating · level \(currentLevel + 1) of \(totalLevels)"
                : "Escalating"
        case .snoozed:
            let t = snoozeUntil?.formatted(date: .omitted, time: .shortened) ?? "—"
            return "Snoozed until \(t)"
        case .done:    return "Done"
        case .stopped: return "Stopped"
        }
    }
}
