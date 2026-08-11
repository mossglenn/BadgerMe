//
//  Radius.swift
//  BadgerKit — design-system corner-radius tokens (P2 design pass; Design Brief A3).
//
//  Distinct radii per component role (never one uniform radius). All rounded rectangles use the
//  `.continuous` (squircle) curve. Status pills use `Capsule()` rather than a fixed radius.
//  Shared by app + widget.
//

import CoreGraphics
#if canImport(SwiftUI)
import SwiftUI
#endif

public enum Radius {
    public static let card:   CGFloat = 16
    public static let button: CGFloat = 12
    public static let input:  CGFloat = 10

    #if canImport(SwiftUI)
    /// The curve style for every rounded rectangle in the app.
    public static let style: RoundedCornerStyle = .continuous
    #endif
}
