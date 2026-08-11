//
//  DesignTokens.swift
//  BadgerKit — the design-system colour tokens (P2 design pass; see Notes/BadgerMe-Design-Brief.md).
//
//  Colour is a PURE escalation-heat signal (identity ⊥ escalation): per-Badger identity lives in the
//  icon SHAPE, colour ramps with heat. These tokens are the single source every surface resolves —
//  the console, the widget, and the Live Activity all reach them through `EscalationTone.color`.
//
//  Code-defined dynamic (light/dark) colours rather than an asset catalog: fully buildable via the
//  package with no resource-processing setup, and unit-testable under `swift test` on the macOS host.
//  Values are PROVISIONAL pending P4 contrast verification (WCAG AA text ≥4.5:1, non-text ≥3:1, both
//  modes). Dark-mode-first; no pure #000/#FFF. Earthy neutrals double as the badger character's own
//  colours (bark fur + bone stripe); the accent is a cool off-ramp denim/slate that also grounds the
//  app icon behind the badger's head.
//

#if canImport(SwiftUI)
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public enum DesignTokens {

    // MARK: - Earthy neutrals (also the badger character's colours)
    public static let surfaceBase     = dyn("#F6F2EC", "#14110E")   // app background
    public static let surfaceElevated = dyn("#FDFBF7", "#1F1B16")   // cards, sheets
    public static let surfaceSunken   = dyn("#EDE7DD", "#100D0B")   // insets, grouped bg
    public static let textPrimary     = dyn("#22201C", "#F2EEE7")   // bark / bone — never #000/#FFF
    public static let textSecondary   = dyn("#6B6459", "#A7A093")   // captions, status
    public static let separator       = dyn("#E4DDD2", "#322C24")   // hairlines

    // MARK: - Escalation heat (the semantic spine): calm → warn → danger
    public static let escCalm         = dyn("#52814D", "#7CA877")   // .identity / armed — fixed cool floor
    public static let escWarn         = dyn("#C77A12", "#E8A33D")   // .warm
    public static let escOverdue      = dyn("#C4531A", "#EE7B39")   // .overdue
    public static let escDanger       = dyn("#B23A2E", "#E5544A")   // .hot — repeating tail
    public static let escMuted        = dyn("#877F72", "#8A8275")   // .muted — snoozed / terminal
    public static let positive        = dyn("#3E7D3F", "#6FB56B")   // Done / all-clear

    // MARK: - Brand accent (OFF the escalation ramp; app-icon ground behind the badger)
    public static let accent          = dyn("#546c8c", "#6E8BB0")   // primary actions + wordmark (app-icon ground)
    public static let onAccent        = dyn("#FFFFFF", "#0F1A20")   // label on accent

    // MARK: - Dynamic-colour builder

    /// "#RRGGBB" → (r, g, b) in 0...1.
    private static func rgb(_ hex: String) -> (Double, Double, Double) {
        var h = Substring(hex)
        if h.first == "#" { h = h.dropFirst() }
        let v = UInt64(h, radix: 16) ?? 0
        return (Double((v >> 16) & 0xFF) / 255.0,
                Double((v >> 8) & 0xFF) / 255.0,
                Double(v & 0xFF) / 255.0)
    }

    /// A Color that resolves `light` in light mode and `dark` in dark mode, on both iOS and macOS.
    private static func dyn(_ light: String, _ dark: String) -> Color {
        let (lr, lg, lb) = rgb(light)
        let (dr, dg, db) = rgb(dark)
        #if canImport(UIKit)
        return Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: dr, green: dg, blue: db, alpha: 1)
                : UIColor(red: lr, green: lg, blue: lb, alpha: 1)
        })
        #elseif canImport(AppKit)
        return Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark
                ? NSColor(red: dr, green: dg, blue: db, alpha: 1)
                : NSColor(red: lr, green: lg, blue: lb, alpha: 1)
        })
        #else
        return Color(red: lr, green: lg, blue: lb)
        #endif
    }
}
#endif
