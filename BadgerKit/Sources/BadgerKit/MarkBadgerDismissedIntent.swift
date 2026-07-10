//
//  MarkBadgerDismissedIntent.swift
//  BadgerKit — the AlarmKit stop-action intent for dismissal logging (M4, §8/§11).
//
//  Wired to AlarmConfiguration.stopIntent so a system Stop appends an `alarmDismissed`
//  event (non-resolving; the ladder continues, §8). Same BadgerEntity-parameter reshape
//  as MarkBadgerDoneIntent; the channel constructs it from the id + rung it holds.
//

import Foundation

#if os(iOS)
import AppIntents

public struct MarkBadgerDismissedIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Mark Badger Alarm Dismissed"

    @Parameter(title: "Badger") public var badger: BadgerEntity
    @Parameter(title: "Rung") public var rung: Int
    @Dependency public var engine: BadgerEngine

    public init() {}
    public init(badgerID: UUID, rung: Int) {
        self.badger = BadgerEntity(id: badgerID)
        self.rung = rung
    }

    public func perform() async throws -> some IntentResult {
        await engine.markAlarmDismissed(badger.id, rung: rung)
        return .result()
    }
}
#endif
