//
//  LAProbe.swift
//  BadgerMe — DEBUG-only Live Activity concurrent-ceiling probe (M7 CP6). Starts dummy ambient
//  activities until iOS refuses, reports the count that succeeded, then cleans them all up. Feeds
//  the D1 (per-Badger vs hybrid-overflow) / D3 (cap) decision. Deliberately bypasses the D3 cap;
//  run it FOREGROUND — background-started activities get a stricter limit.
//

#if DEBUG
import Foundation
import ActivityKit
import BadgerKit

enum LAProbe {
    @MainActor
    static func measureCeiling(max: Int = 15) async -> String {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return "Live Activities are disabled in Settings"
        }
        var started: [Activity<BadgerActivityAttributes>] = []
        var threw: (index: Int, message: String)?
        for i in 1...max {
            let attributes = BadgerActivityAttributes(badgerID: UUID(), title: "Probe \(i)", tint: "accent")
            let state = BadgerActivityAttributes.ContentState(
                currentLevelIndex: 0, totalLevels: 1, nextFireDate: nil, phase: .armed)
            do {
                let activity = try Activity.request(
                    attributes: attributes,
                    content: ActivityContent(state: state, staleDate: nil))
                started.append(activity)
            } catch {
                threw = (i, error.localizedDescription)
                break
            }
        }
        let count = started.count
        for activity in started { await activity.end(nil, dismissalPolicy: .immediate) }
        if let threw {
            return "LA ceiling \u{2248} \(count) (request #\(threw.index) threw: \(threw.message))"
        }
        return "started \(count) with no throw (ceiling \u{2265} \(max))"
    }
}
#endif
