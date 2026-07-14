//
//  GetActiveBadgersIntent.swift
//  BadgerKit — "what's badgering me" (M4/§11; interactive card added M5 CP4b).
//
//  Returns a spoken summary + an interactive snippet card (ActiveBadgersSnippetIntent) with a
//  Done/Snooze button per active Badger. The 26.5 AppIntents .swiftinterface has no result
//  factory combining a returned value with a snippet, so this returns `dialog + snippetIntent`
//  and drops the earlier (unused) `[BadgerEntity]` value (CP4b Option A). The App Shortcut wiring
//  is unchanged — it still points at this intent.
//

import Foundation

#if os(iOS)
import AppIntents

@available(iOS 26.0, *)
public struct GetActiveBadgersIntent: AppIntent {
    public static let title: LocalizedStringResource = "Get Active Badgers"
    public static let description = IntentDescription("List the Badgers currently escalating.")

    @Dependency public var engine: BadgerEngine

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetIntent {
        let count = await engine.activeSnapshots().count
        let dialog: IntentDialog = count == 0
            ? "Nothing is badgering you right now."
            : "You have \(count) active \(count == 1 ? "Badger" : "Badgers")."
        return .result(dialog: dialog, snippetIntent: ActiveBadgersSnippetIntent())
    }
}
#endif
