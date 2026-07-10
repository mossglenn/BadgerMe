//
//  BadgerActionIntents.swift
//  BadgerKit — the per-Badger action intents (M4, §11). Each is a thin dispatch to the
//  shared engine; no escalation logic lives here (L3). Snooze backs a Live-Activity
//  button (LiveActivityIntent); Stop/Replace/Edit/Delete/Open are Siri/Shortcuts actions
//  running in-app where the engine @Dependency is registered.
//

import Foundation

#if os(iOS)
import AppIntents

public struct SnoozeBadgerIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Snooze Badger"

    @Parameter(title: "Badger") public var badger: BadgerEntity
    @Parameter(title: "Minutes", default: 15) public var minutes: Int
    @Dependency public var engine: BadgerEngine

    public init() {}
    public init(badgerID: UUID, minutes: Int = 15) {
        self.badger = BadgerEntity(id: badgerID)
        self.minutes = minutes
    }

    public func perform() async throws -> some IntentResult {
        await engine.snooze(badger.id, duration: TimeInterval(max(1, minutes) * 60))
        return .result()
    }
}

public struct StopBadgerIntent: AppIntent {
    public static let title: LocalizedStringResource = "Stop Badger"
    public static let description = IntentDescription("Stop escalating a Badger (kept in history).")

    @Parameter(title: "Badger") public var badger: BadgerEntity
    @Dependency public var engine: BadgerEngine

    public init() {}

    public func perform() async throws -> some IntentResult {
        try await requestConfirmation(dialog: "Stop badgering \(badger.title)?")
        await engine.stop(badger.id)
        return .result()
    }
}

public struct ReplaceBadgerIntent: AppIntent {
    public static let title: LocalizedStringResource = "Replace Badger"
    public static let description = IntentDescription("Re-run a finished Badger from the start.")

    @Parameter(title: "Badger") public var badger: BadgerEntity
    @Dependency public var engine: BadgerEngine

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<BadgerEntity> {
        let snap = await engine.replace(badger.id)
        return .result(value: snap.map(BadgerEntity.init) ?? badger)
    }
}

public struct EditBadgerIntent: AppIntent {
    public static let title: LocalizedStringResource = "Edit Badger"

    @Parameter(title: "Badger") public var badger: BadgerEntity
    @Parameter(title: "New Title") public var newTitle: String?
    @Parameter(title: "New Notes") public var newNotes: String?
    @Dependency public var engine: BadgerEngine

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<BadgerEntity> {
        // D2 baseline: title/notes edits; schedule edits are a console/later concern.
        let snap = await engine.edit(badger.id, title: newTitle, notes: newNotes)
        return .result(value: snap.map(BadgerEntity.init) ?? badger)
    }
}

public struct DeleteBadgerIntent: AppIntent {
    public static let title: LocalizedStringResource = "Delete Badger"
    public static let description = IntentDescription("Delete a Badger and its history.")

    @Parameter(title: "Badger") public var badger: BadgerEntity
    @Dependency public var engine: BadgerEngine

    public init() {}

    public func perform() async throws -> some IntentResult {
        try await requestConfirmation(dialog: "Delete \(badger.title) and its history?")
        await engine.delete(badger.id)
        return .result()
    }
}

public struct OpenBadgerIntent: OpenIntent {
    public static let title: LocalizedStringResource = "Open Badger"

    @Parameter(title: "Badger") public var target: BadgerEntity

    public init() {}
    public init(target: BadgerEntity) { self.target = target }

    public func perform() async throws -> some IntentResult { .result() }
}
#endif
