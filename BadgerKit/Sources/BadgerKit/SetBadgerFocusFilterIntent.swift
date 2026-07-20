//
//  SetBadgerFocusFilterIntent.swift
//  BadgerKit — the per-Focus escalation filter (§13, M6 CP4).
//
//  Two orthogonal controls (§13): a `onlyTag` scope (which Badgers escalate — off-tag Badgers
//  are held) and an escalation `cap` (how loud). perform() pushes both into the engine, which
//  re-arms live Badgers with the cap applied at arm time. SP14 (device-verified) confirmed
//  perform() fires on every Focus change foreground/background/force-quit, so no App Intents
//  extension (D7) and no LiveActivityIntent workaround are needed.
//
//  Lives in the package (spec §4) so Xcode 26 auto-discovers it — NO AppIntentsPackage decl
//  (removed in fix M4). #if os(iOS): AppIntents is iOS-only; BadgerKit still builds on macOS.
//

import Foundation

#if os(iOS)
import AppIntents

/// User-facing escalation cap for a Focus. Maps to a max `Prominence` the engine enforces.
public enum FocusEscalationCap: String, AppEnum {
    case breakthrough    // allow everything (no cap)
    case timeSensitive   // no breakthrough alarms
    case quiet           // passive only

    public static var typeDisplayRepresentation: TypeDisplayRepresentation { "Escalation Cap" }
    public static var caseDisplayRepresentations: [FocusEscalationCap: DisplayRepresentation] {
        [.breakthrough: "Allow breakthrough alarms",
         .timeSensitive: "Cap at time-sensitive",
         .quiet: "Quiet only"]
    }

    /// The max prominence this cap allows; nil = no cap (breakthrough permitted).
    public var prominenceCap: Prominence? {
        switch self {
        case .breakthrough:  return nil
        case .timeSensitive: return .timeSensitive
        case .quiet:         return .passive
        }
    }
}

/// Supplies the tags Badgers currently carry, for the `onlyTag` scope parameter (§13).
public struct FocusTagOptionsProvider: DynamicOptionsProvider {
    @Dependency public var engine: BadgerEngine
    public init() {}
    public func results() async throws -> [String] { await engine.allFocusTags() }
}

/// Tune BadgerMe escalation for a Focus: restrict which Badgers escalate (by tag) and cap how
/// loud they get. Both parameters are Optional (SetFocusFilterIntent requires it — SP14).
public struct SetBadgerFocusFilterIntent: SetFocusFilterIntent {
    public static let title: LocalizedStringResource = "Set BadgerMe Focus Filter"
    public static let description =
        IntentDescription("Limit which Badgers escalate, and how loud, during this Focus.")

    @Parameter(title: "Only Badgers tagged", optionsProvider: FocusTagOptionsProvider())
    public var onlyTag: String?

    @Parameter(title: "Maximum escalation")
    public var cap: FocusEscalationCap?

    @Dependency public var engine: BadgerEngine

    public init() {}

    public var displayRepresentation: DisplayRepresentation {
        let scope = onlyTag.map { "#\($0)" } ?? "all Badgers"
        let loud: String
        switch cap {
        case .timeSensitive: loud = "time-sensitive max"
        case .quiet:         loud = "quiet"
        case .breakthrough, .none: loud = "full escalation"
        }
        return DisplayRepresentation(title: "\(scope) · \(loud)")
    }

    public func perform() async throws -> some IntentResult {
        await engine.applyFocusFilter(cap: cap?.prominenceCap, onlyTag: onlyTag)
        return .result()
    }
}
#endif
