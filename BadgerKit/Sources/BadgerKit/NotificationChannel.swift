//
//  NotificationChannel.swift
//  BadgerKit — the `notification` AlertChannel (Phase 5 §9/§10), soft rungs.
//
//  UserNotifications-backed. Not observable at fire (no app code runs at delivery,
//  P2) — awareness comes from taps (delegate) and reconcile (§14). The last-rung
//  repeat is a bounded batch of one-shot requests (`…-rep-{n}`), replenished on
//  reconcile in M6 (SP3: no arbitrary-interval recurrence on any v1 channel).
//

import Foundation
import UserNotifications

/// Category + action identifiers and the reducer-facing action vocabulary (§8).
/// Notification action buttons route ONLY through UNUserNotificationCenterDelegate
/// (no `Button(intent:)` on notifications), so this is the permanent path for
/// resolve-from-notification; M4 adds Siri/Shortcut/widget entry points that call the
/// same engine methods.
public enum BadgerNotifications {
    public static let categoryID = "BADGER_ALERT"
    public static let doneActionID = "BADGER_DONE"
    public static let snoozeActionID = "BADGER_SNOOZE"

    /// The one category all Badger alerts carry: expandable "I did it" + "Snooze".
    /// Both non-foreground, so the system background-launches the app to run the
    /// delegate headlessly (in the app's own process — DI resolves; this is not the
    /// widget-process question of SP10).
    public static func category() -> UNNotificationCategory {
        let done = UNNotificationAction(identifier: doneActionID, title: "I did it", options: [])
        let snooze = UNNotificationAction(identifier: snoozeActionID, title: "Snooze", options: [])
        return UNNotificationCategory(identifier: categoryID, actions: [done, snooze],
                                      intentIdentifiers: [], options: [])
    }

    /// The pending-request identifier for a Badger's ladder slot (deterministic, so
    /// teardown can prefix-scan). `badger-{uuid}-rung-{k}` / `-rung-{k}-rep-{n}` / `-wake`.
    public static func identifier(badgerID: UUID, slot: ScheduleSlot) -> String {
        let base = "badger-\(badgerID.uuidString)"
        switch slot {
        case .rung(let k):                  return "\(base)-rung-\(k)"
        case .repeatTail(let rung, let n):  return "\(base)-rung-\(rung)-rep-\(n)"
        case .wake:                         return "\(base)-wake"
        }
    }

    /// Prefix matching every request this Badger owns (for cancelAll).
    public static func identifierPrefix(badgerID: UUID) -> String {
        "badger-\(badgerID.uuidString)-"
    }

    /// Extract the owning Badger id from a delivered/response notification.
    public static func badgerID(from userInfo: [AnyHashable: Any]) -> UUID? {
        (userInfo["badgerID"] as? String).flatMap(UUID.init(uuidString:))
    }
}

public struct NotificationChannel: AlertChannel {
    public let id = "notification"
    public let capabilities = ChannelCapabilities(
        prominences: [.passive, .active, .timeSensitive],
        deliversInBackground: true,
        observableAtFire: false,
        needsWidget: false,
        supportsArbitraryRecurrence: false)

    private var center: UNUserNotificationCenter { .current() }

    public init() {}

    public func schedule(_ action: ChannelAction, at fireDate: Date,
                         recurrence: ChannelRecurrence?, badgerID: UUID,
                         slot: ScheduleSlot) async throws -> ScheduledRef {
        let content = UNMutableNotificationContent()
        content.title = action.message ?? "BadgerMe"
        content.interruptionLevel = interruptionLevel(for: action.prominence)
        content.sound = sound(for: action.soundRef)
        content.categoryIdentifier = BadgerNotifications.categoryID
        content.userInfo = ["badgerID": badgerID.uuidString, "slot": slotTag(slot)]

        // ≤60 s fires (and the arm-ahead ladder generally) use an interval trigger,
        // not a calendar trigger (§20 near-future cliff). Clamp > 0; a fire date at
        // or before now (e.g. rung 0 at +0, or a reconcile catch-up) becomes imminent.
        let interval = max(fireDate.timeIntervalSinceNow, 1)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)

        let identifier = BadgerNotifications.identifier(badgerID: badgerID, slot: slot)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try await center.add(request)
        return ScheduledRef(channelID: id, identifier: identifier, slot: slot)
    }

    public func cancel(_ ref: ScheduledRef) async {
        center.removePendingNotificationRequests(withIdentifiers: [ref.identifier])
        center.removeDeliveredNotifications(withIdentifiers: [ref.identifier])
    }

    public func cancelAll(forBadgerID badgerID: UUID) async {
        let prefix = BadgerNotifications.identifierPrefix(badgerID: badgerID)
        let pendingIDs = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(prefix) }
        let deliveredIDs = await center.deliveredNotifications()
            .map(\.request.identifier)
            .filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pendingIDs)
        center.removeDeliveredNotifications(withIdentifiers: deliveredIDs)
    }

    // MARK: - Mapping

    private func interruptionLevel(for p: Prominence) -> UNNotificationInterruptionLevel {
        switch p {
        case .passive:       return .passive
        case .active:        return .active
        case .timeSensitive: return .timeSensitive
        case .breakthrough:  return .timeSensitive   // notifications can't pierce silent; alarmkit does (M3)
        }
    }

    private func sound(for ref: SoundRef?) -> UNNotificationSound {
        switch ref {
        case .none:              return .default
        case .builtIn:           return .default            // curated catalog is M7/D10
        case .imported(let f):   return UNNotificationSound(named: UNNotificationSoundName(f))  // bundle or Library/Sounds (§20)
        case .renderedSpeech:    return .default            // D11 fast-follow
        }
    }

    private func slotTag(_ slot: ScheduleSlot) -> String {
        switch slot {
        case .rung(let k):                  return "rung:\(k)"
        case .repeatTail(let rung, let n):  return "rep:\(rung):\(n)"
        case .wake:                         return "wake"
        }
    }
}
