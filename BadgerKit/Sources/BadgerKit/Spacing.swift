//
//  Spacing.swift
//  BadgerKit — design-system spacing tokens (P2 design pass; Design Brief A3).
//
//  One 8 pt scale (4 pt fine step); 16 pt screen margins. Use `@ScaledMetric` at call sites when
//  spacing must grow with Dynamic Type next to text. Shared by app + widget.
//

import CoreGraphics

public enum Space {
    public static let xxs: CGFloat = 4
    public static let xs:  CGFloat = 8
    public static let sm:  CGFloat = 12
    public static let md:  CGFloat = 16
    public static let lg:  CGFloat = 24
    public static let xl:  CGFloat = 32
    public static let xxl: CGFloat = 48

    /// Standard screen margin (iPhone).
    public static let screenMargin: CGFloat = 16
}
