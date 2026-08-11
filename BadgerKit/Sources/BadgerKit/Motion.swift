//
//  Motion.swift
//  BadgerKit — design-system motion tokens (P2 design pass; Design Brief A8).
//
//  Springs, not eases — interruptible and native. Purposeful only: Done collapse, rung-climb heat
//  shift, snooze settle. Gate on `accessibilityReduceMotion` at call sites (reduce, don't remove).
//  Shared by app + widget.
//

#if canImport(SwiftUI)
import SwiftUI

public enum Motion {
    /// State changes: Done collapse, rung-climb heat transition, snooze settle.
    public static let standard: Animation = .spring(response: 0.55, dampingFraction: 0.825)

    /// Gesture-driven interactions (swipes, drags).
    public static let interactive: Animation = .interactiveSpring(response: 0.4, dampingFraction: 0.8)
}
#endif
