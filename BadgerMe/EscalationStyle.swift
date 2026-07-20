//
//  EscalationStyle.swift
//  BadgerMe — SwiftUI adapter over BadgerKit's pure EscalationPalette (§16, M7 CP3).
//
//  The palette DECIDES a tone (Foundation-only, tested); this maps tone + identity-tint token to a
//  concrete Color for the console. It duplicates the widget's private resolveTint for now; a later
//  checkpoint (CP6) unifies the widget's copies onto a single shared adapter. Colour is always
//  paired with a text/symbol status in the views (never colour-only) for accessibility (§16).
//

import SwiftUI
import SwiftData
import BadgerKit

enum EscalationStyle {
    /// Resolve a Badger identity-tint token (from EscalationPalette.identityTints) to a Color.
    static func tintColor(_ token: String?) -> Color {
        switch token {
        case "red":          return .red
        case "orange":       return .orange
        case "yellow":       return .yellow
        case "green":        return .green
        case "mint":         return .mint
        case "teal":         return .teal
        case "cyan":         return .cyan
        case "blue":         return .blue
        case "indigo":       return .indigo
        case "purple":       return .purple
        case "pink":         return .pink
        case "brown":        return .brown
        case "gray", "grey": return .gray
        default:             return .accentColor
        }
    }

    /// Map an escalation tone to a colour; `.identity` resolves the Badger's own tint token.
    static func color(_ tone: EscalationTone, tint: String?) -> Color {
        switch tone {
        case .identity: return tintColor(tint)
        case .warm:     return .orange
        case .hot:      return .red
        case .muted:    return .gray
        case .overdue:  return .orange
        }
    }

    /// Derive the ambient phase from a persisted Badger's state (the console has no live LA phase).
    /// `active` at the last rung is the repeating tail. `isStale` is false in the console (live view).
    static func phase(state: StoredBadgerState, currentLevel: Int, totalLevels: Int) -> BadgerActivityPhase {
        switch state {
        case .pending: return .armed
        case .active:  return currentLevel >= max(0, totalLevels - 1) ? .repeating : .escalating
        case .snoozed: return .snoozed
        case .done:    return .done
        case .stopped: return .stopped
        }
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
    var escalationColor: Color { EscalationStyle.color(escalationTone, tint: tint) }

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
