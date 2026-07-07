//
//  AppDelegate.swift
//  BadgerMe — composition root (L11) + notification delegate (§9/§14).
//
//  Owns the single App-Group ModelContainer and the single BadgerEngine, wires the
//  notification categories, and routes taps/actions and foreground deliveries into
//  the engine. Notification action buttons route ONLY through this delegate (there is
//  no Button(intent:) on notifications); M4 adds Siri/Shortcut/widget entry points
//  that call the same engine methods. Using an app delegate keeps the @MainActor
//  engine's construction on the main actor and gives the classic launch hook.
//

import UIKit
import UserNotifications
import SwiftData
import BadgerKit

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    let container: ModelContainer
    let engine: BadgerEngine

    /// App-wide default snooze until Settings exists (§16/D6, M7).
    private let defaultSnooze: TimeInterval = 9 * 60

    override init() {
        // Shared App-Group store (§4) so the widget/intents can read state later.
        let container = try! makeModelContainer(groupContainerID: "group.com.badgerme.shared")
        self.container = container
        var registry = AlertChannelRegistry()
        registry.register(NotificationChannel())          // M3 also registers `alarmkit`
        self.engine = BadgerEngine(container: container, registry: registry)
        super.init()
    }

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions:
                        [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([BadgerNotifications.category()])
        Task { _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge]) }
        return true
    }

    // A soft rung fired while the app is foreground: advance that Badger now + show it.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        if let id = BadgerNotifications.badgerID(from: notification.request.content.userInfo) {
            await engine.handleForegroundDelivery(badgerID: id)
        }
        return [.banner, .sound, .list]
    }

    // Tap on the body, "I did it", or "Snooze" (runs even if the app was killed —
    // the system background-launches this process, so the engine's DI is available).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let id = BadgerNotifications.badgerID(from: info) else { return }
        await engine.handleNotificationResponse(badgerID: id,
                                                actionID: response.actionIdentifier,
                                                defaultSnooze: defaultSnooze)
    }
}
