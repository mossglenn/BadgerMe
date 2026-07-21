//
//  Haptics.swift
//  BadgerMe — haptic confirmation on user actions (§16 accessibility bar, M7 CP6).
//  UIImpactFeedbackGenerator per the spec; a light tap for reversible actions, heavier for
//  destructive ones, and a success notification for resolving a Badger.
//

import UIKit

enum Haptics {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
