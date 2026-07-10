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
import AppIntents
import BadgerKit
#if canImport(AlarmKit)
import AlarmKit
#endif

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    let container: ModelContainer
    let engine: BadgerEngine

    #if DEBUG
    /// SP9/B1 device diagnostic: probe the per-app AlarmKit alarm ceiling. nil if no AlarmKit.
    let debugProbeCeiling: (@Sendable () async -> Int)?
    #endif

    /// App-wide default snooze until Settings exists (§16/D6, M7).
    private let defaultSnooze: TimeInterval = 9 * 60

    override init() {
        // Shared App-Group store (§4) so the widget/intents can read state later.
        let container = try! makeModelContainer(groupContainerID: "group.com.badgerme.shared")
        self.container = container
        var registry = AlertChannelRegistry()
        registry.register(NotificationChannel())
        #if canImport(AlarmKit)
        let alarmChannel = AlarmKitChannel()   // hard/breakthrough rungs (M3); app floor is iOS 26.1 (D9)
        registry.register(alarmChannel)
        #if DEBUG
        debugProbeCeiling = { await alarmChannel.probeCeiling() }   // SP9/B1 diagnostic
        #endif
        #else
        #if DEBUG
        debugProbeCeiling = nil
        #endif
        #endif
        let engine = BadgerEngine(container: container, registry: registry)
        self.engine = engine
        // L11/§11: register the shared engine so in-app intents (the alarm's "I did it"
        // secondary button, MarkBadgerDoneIntent) resolve it via @Dependency.
        AppDependencyManager.shared.add(dependency: engine)
        super.init()
    }

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions:
                        [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([BadgerNotifications.category()])
        Task { _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge]) }
        #if canImport(AlarmKit)
        // AlarmKit auth is self-service (SP1) — no Apple approval. Needed before any hard
        // rung can arm; full permission onboarding with rationale is M7/§17.
        Task { _ = try? await AlarmManager.shared.requestAuthorization() }
        #endif
        // Rehydrate the AlarmKit owner map from persisted armedAlarms BEFORE observing, so a
        // prior-process alarm firing is attributed after a relaunch (M3 cold-kill fix, ckpt 4).
        Task { @MainActor in
            await engine.rehydrateArmedAlarms()
            engine.startObserving()   // consume AlarmKit's live lifecycle stream (§14 path 1)
        }
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
