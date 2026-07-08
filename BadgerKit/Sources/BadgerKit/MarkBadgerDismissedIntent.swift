//
//  MarkBadgerDismissedIntent.swift
//  BadgerKit — the AlarmKit stop-action intent for dismissal logging.
//

import Foundation

#if os(iOS)
import AppIntents

struct MarkBadgerDismissedIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Mark Badger Alarm Dismissed"

    @Parameter(title: "Badger ID") var badgerID: String
    @Parameter(title: "Rung") var rung: Int
    @Dependency var engine: BadgerEngine

    init() {}
    init(badgerID: String, rung: Int) {
        self.badgerID = badgerID
        self.rung = rung
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: badgerID) {
            await engine.markAlarmDismissed(id, rung: rung)
        }
        return .result()
    }
}
#endif
