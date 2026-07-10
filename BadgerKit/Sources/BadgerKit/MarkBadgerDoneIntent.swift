//
//  MarkBadgerDoneIntent.swift
//  BadgerKit — the resolve-from-alarm / catalog "mark done" App Intent (M4, §11).
//
//  AlarmKit's AlarmConfiguration.secondaryIntent is `(any LiveActivityIntent)?` (verified
//  against the 26.5 .swiftinterface), and LiveActivityIntents run IN the app process,
//  where AppDelegate registers the engine as an @Dependency (L11/§11) — so this resolves
//  the same shared engine the console / notification delegate use.
//
//  The parameter is a BadgerEntity (the Siri/Shortcuts surface) rather than a raw id;
//  the AlarmKit secondary button / Live-Activity Done button construct it from the id
//  they hold via `init(badgerID:)`. When App Intents re-resolves the parameter through
//  BadgerQuery, the display fields refresh; perform() only needs `badger.id`. (Headless
//  entity re-resolution in the force-quit alarm process is an SP4/SP10-adjacent device
//  re-check — see the M4 device-verify note.)
//
//  #if os(iOS): LiveActivityIntent / Live Activities are iOS-only, keeping BadgerKit
//  compiling on macOS for `swift test`.
//

import Foundation

#if os(iOS)
import AppIntents

public struct MarkBadgerDoneIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Mark Badger Done"

    @Parameter(title: "Badger") public var badger: BadgerEntity
    @Dependency public var engine: BadgerEngine

    public init() {}

    /// The AlarmKit secondary button / Live-Activity Done button hold only the id.
    public init(badgerID: UUID) { self.badger = BadgerEntity(id: badgerID) }

    public func perform() async throws -> some IntentResult {
        await engine.markDone(badger.id)
        return .result()
    }
}
#endif
