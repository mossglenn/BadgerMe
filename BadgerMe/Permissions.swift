//
//  Permissions.swift
//  BadgerMe — the app's view of notification + AlarmKit authorization (§17). Reads current state
//  and drives the runtime requests from onboarding / Settings, so prompts appear with rationale
//  rather than fire-and-forget at launch. No Critical Alerts (L12).
//

import Foundation
import Observation
import UserNotifications
import AlarmKit

@MainActor
@Observable
final class Permissions {
    var notifications: UNAuthorizationStatus = .notDetermined
    var alarms: AlarmManager.AuthorizationState = .notDetermined

    /// True once both prompts have been answered one way or another (used to advance onboarding).
    var notificationsDecided: Bool { notifications != .notDetermined }
    var alarmsDecided: Bool { alarms != .notDetermined }

    func refresh() async {
        notifications = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        alarms = AlarmManager.shared.authorizationState
    }

    @discardableResult
    func requestNotifications() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refresh()
        return granted
    }

    @discardableResult
    func requestAlarms() async -> Bool {
        let state = (try? await AlarmManager.shared.requestAuthorization()) ?? .notDetermined
        await refresh()
        return state == .authorized
    }
}

extension UNAuthorizationStatus {
    var label: String {
        switch self {
        case .authorized, .provisional, .ephemeral: return "Allowed"
        case .denied:                               return "Denied"
        case .notDetermined:                        return "Not set"
        @unknown default:                           return "Unknown"
        }
    }
    var isAllowed: Bool {
        self == .authorized || self == .provisional || self == .ephemeral
    }
}

extension AlarmManager.AuthorizationState {
    var label: String {
        switch self {
        case .authorized:    return "Allowed"
        case .denied:        return "Denied"
        case .notDetermined: return "Not set"
        @unknown default:    return "Unknown"
        }
    }
}
