//
//  MarkBadgerDoneIntent.swift
//  BadgerKit — the resolve-from-alarm App Intent (a minimal M4 slice pulled into M3).
//
//  AlarmKit's AlarmConfiguration.secondaryIntent is typed `(any LiveActivityIntent)?`
//  (verified against the iOS 26.5 .swiftinterface), so the hard-rung "I did it" button
//  must be a LiveActivityIntent. LiveActivityIntents run IN the app process, where the
//  composition root (AppDelegate) registers the engine as an @Dependency (L11/§11) — so
//  this resolves the same shared engine the console and notification delegate use. The
//  full entity/query/intent catalog + App Shortcuts stay M4; this is only the button the
//  M3 alarm channel needs (SP4 is the device spike for this path).
//
//  Guarded `#if os(iOS)` because LiveActivityIntent / Live Activities are iOS-only,
//  keeping the package compiling on macOS for `swift test`.
//

import Foundation

#if os(iOS)
import AppIntents

struct MarkBadgerDoneIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Mark Badger Done"

    @Parameter(title: "Badger ID") var badgerID: String
    @Dependency var engine: BadgerEngine

    init() {}
    init(badgerID: String) { self.badgerID = badgerID }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: badgerID) { await engine.markDone(id) }
        return .result()
    }
}
#endif
