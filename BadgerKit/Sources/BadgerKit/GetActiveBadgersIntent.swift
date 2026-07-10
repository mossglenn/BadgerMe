//
//  GetActiveBadgersIntent.swift
//  BadgerKit — "what's badgering me" (M4, §11).
//
//  Returns the active Badgers + a spoken summary. The interactive snippet card
//  (SnippetIntent-driven, per-Badger Done/Snooze buttons) is deferred to CP5, where the
//  snippet UI is built alongside the widgets; the value + dialog here already answer the
//  query for Siri/Shortcuts.
//

import Foundation

#if os(iOS)
import AppIntents

public struct GetActiveBadgersIntent: AppIntent {
    public static let title: LocalizedStringResource = "Get Active Badgers"
    public static let description = IntentDescription("List the Badgers currently escalating.")

    @Dependency public var engine: BadgerEngine

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<[BadgerEntity]> & ProvidesDialog {
        let entities = await engine.activeSnapshots().map(BadgerEntity.init)
        let dialog: IntentDialog = entities.isEmpty
            ? "Nothing is badgering you right now."
            : "You have \(entities.count) active \(entities.count == 1 ? "Badger" : "Badgers")."
        return .result(value: entities, dialog: dialog)
    }
}
#endif
