//
//  LiveActivityController.swift
//  BadgerKit — the real ambient Live Activity controller (§12, M5 CP2b).
//
//  Drives the per-Badger BadgerActivityAttributes activity via ActivityKit. Internal +
//  guarded #if os(iOS): ActivityPhase is internal to the locked core, so this can't be a
//  public conformer — instead BadgerEngine defaults to it on iOS (the app never names it).
//  Stateless: it locates the live activity by matching attributes.badgerID in
//  Activity.activities, so it needs no stored handles and no ModelContainer. The ambient
//  activity is best-effort polish (§12) — every ActivityKit call is guarded/try? and
//  silently no-ops when Live Activities are disabled or unavailable; it never affects the
//  reliable AlarmKit/notification schedule.
//

#if os(iOS)
import Foundation
import ActivityKit

struct LiveActivityController: LiveActivityControlling {

    func start(badgerID: UUID, title: String, tint: String?, iconName: String?, phase: ActivityPhase,
               level: Int, totalLevels: Int, nextFire: Date?) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // If one is somehow already live for this Badger, update rather than duplicate.
        if activity(for: badgerID) != nil {
            await update(badgerID: badgerID, phase: phase, level: level,
                         totalLevels: totalLevels, nextFire: nextFire)
            return
        }
        let attributes = BadgerActivityAttributes(badgerID: badgerID, title: title, tint: tint, iconName: iconName)
        let content = ActivityContent(
            state: contentState(phase: phase, level: level, totalLevels: totalLevels, nextFire: nextFire),
            staleDate: nextFire)   // §12: staleDate == nextFireDate → system flips to stale
        _ = try? Activity.request(attributes: attributes, content: content)
    }

    func update(badgerID: UUID, phase: ActivityPhase,
                level: Int, totalLevels: Int, nextFire: Date?) async {
        guard let activity = activity(for: badgerID) else { return }
        let content = ActivityContent(
            state: contentState(phase: phase, level: level, totalLevels: totalLevels, nextFire: nextFire),
            staleDate: nextFire)
        await activity.update(content)
    }

    func end(badgerID: UUID, terminalPhase: ActivityPhase?) async {
        guard let activity = activity(for: badgerID) else { return }
        guard let terminalPhase else {
            await activity.end(using: nil, dismissalPolicy: .immediate)   // delete / non-terminal teardown
            return
        }
        // Terminal beat (§16, code review #7): hold "Done"/"Stopped" briefly, then clear.
        await activity.end(
            using: contentState(phase: terminalPhase, level: 0, totalLevels: 0, nextFire: nil),
            dismissalPolicy: .after(Date().addingTimeInterval(4)))
    }

    // MARK: - Helpers

    private func activity(for badgerID: UUID) -> Activity<BadgerActivityAttributes>? {
        Activity<BadgerActivityAttributes>.activities.first { $0.attributes.badgerID == badgerID }
    }

    private func contentState(phase: ActivityPhase, level: Int, totalLevels: Int,
                              nextFire: Date?) -> BadgerActivityAttributes.ContentState {
        BadgerActivityAttributes.ContentState(
            currentLevelIndex: level, totalLevels: totalLevels,
            nextFireDate: nextFire, phase: mapPhase(phase))
    }

    private func mapPhase(_ p: ActivityPhase) -> BadgerActivityAttributes.Phase {
        switch p {
        case .armed:      return .armed
        case .escalating: return .escalating
        case .repeating:  return .repeating
        case .snoozed:    return .snoozed
        case .done:       return .done
        case .stopped:    return .stopped
        case .overdue:    return .overdue
        }
    }
}
#endif
