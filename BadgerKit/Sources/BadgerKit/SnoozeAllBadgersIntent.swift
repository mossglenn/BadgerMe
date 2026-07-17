//
//  SnoozeAllBadgersIntent.swift
//  BadgerKit — the "Snooze all" Control Center action (M6 CP3, §11).
//
//  Snoozes every actively-escalating Badger in one tap. A plain AppIntent: it runs in-app via
//  @Dependency (the control background-launches the app process, exactly like the notification
//  Done/Snooze actions — no foregrounding, openAppWhenRun stays false). Snooze is reversible
//  and non-destructive, and Control Center buttons can't prompt, so there's no confirmation.
//  Discoverable, so it doubles as a Siri/Shortcuts action ("Snooze all my badgers").
//
//  #if os(iOS): AppIntents is iOS-only here; BadgerKit keeps compiling on macOS for
//  `swift test` (the engine.snoozeAllActive it dispatches to is tested there).
//

import Foundation

#if os(iOS)
import AppIntents

public struct SnoozeAllBadgersIntent: AppIntent {
    public static let title: LocalizedStringResource = "Snooze All Badgers"
    public static let description = IntentDescription(
        "Snooze every actively escalating Badger for the default snooze duration.")

    @Dependency public var engine: BadgerEngine

    public init() {}

    public func perform() async throws -> some IntentResult {
        await engine.snoozeAllActive(duration: BadgerConfig.defaultSnoozeDuration)
        return .result()
    }
}
#endif
