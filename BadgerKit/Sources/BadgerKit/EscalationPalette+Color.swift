//
//  EscalationPalette+Color.swift
//  BadgerKit — the SwiftUI colour mapping for the escalation palette (§16, M7 CP6).
//
//  The pure `EscalationPalette.tone` decision plus this mapping are the SINGLE source the console,
//  the widget, and the Live Activity all use — replacing each surface's previously-duplicated
//  `resolveTint` / `escalationTint`. SwiftUI is available on every BadgerKit platform, so this is
//  guarded on `canImport` rather than a specific OS.
//

#if canImport(SwiftUI)
import SwiftUI

public extension EscalationPalette {
    /// Resolve an identity-tint token (see `identityTints`) to a Color; unknown / `accent` → accent.
    /// DEPRECATED (P2 design pass): per-Badger identity is the icon SHAPE now, not a tint colour, so
    /// this resolver + `identityTints` are vestigial — removed once the widget/console stop tinting
    /// by identity (they tint by escalation heat via `EscalationTone.color`).
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
}

public extension EscalationTone {
    /// The concrete colour for this tone. Colour is a PURE escalation-heat signal (P2 design pass):
    /// per-Badger identity lives in the icon SHAPE, not colour, so `tint` is ignored here (kept with a
    /// default for source compatibility; dropped when the widget surface moves the icon onto heat).
    /// Resolves to `DesignTokens`, not raw system colours.
    func color(tint: String? = nil) -> Color {
        switch self {
        case .identity: return DesignTokens.escCalm
        case .warm:     return DesignTokens.escWarn
        case .hot:      return DesignTokens.escDanger
        case .muted:    return DesignTokens.escMuted
        case .overdue:  return DesignTokens.escOverdue
        }
    }
}
#endif
