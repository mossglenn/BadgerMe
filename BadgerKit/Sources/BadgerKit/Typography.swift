//
//  Typography.swift
//  BadgerKit — design-system typography tokens (P2 design pass; Design Brief A1).
//
//  Two system faces, one role each. SF Pro (Dynamic Type text styles) is the interface workhorse,
//  used directly as `.headline` / `.body` / etc. New York (serif) is the badger's editorial VOICE
//  (empty states, onboarding, the ambient status line). Countdowns use monospaced digits.
//  ≤3 sizes per screen; hierarchy = size + weight + colour. No fixed sizes (Dynamic Type).
//  Lives in BadgerKit so the app and the widget share one design system.
//

#if canImport(SwiftUI)
import SwiftUI

public extension Font {
    /// The badger's editorial voice — New York serif, full Dynamic Type. Reserve for editorial
    /// moments (empty states, onboarding, status quips), not interface chrome.
    static func badgerVoice(_ style: Font.TextStyle = .body) -> Font {
        .system(style, design: .serif)
    }

    /// Numeric / countdown readouts — SF Pro with monospaced digits, Dynamic Type.
    static func badgerNumeric(_ style: Font.TextStyle = .body) -> Font {
        .system(style, design: .default).monospacedDigit()
    }
}
#endif
