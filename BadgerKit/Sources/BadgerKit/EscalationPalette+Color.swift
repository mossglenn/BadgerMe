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
    /// The concrete colour for this tone; `.identity` resolves the Badger's own tint token.
    func color(tint: String?) -> Color {
        switch self {
        case .identity: return EscalationPalette.tintColor(tint)
        case .warm:     return .orange
        case .hot:      return .red
        case .muted:    return .gray
        case .overdue:  return .orange
        }
    }
}
#endif
