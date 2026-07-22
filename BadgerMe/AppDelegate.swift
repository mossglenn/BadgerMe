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

    /// App-wide default snooze, sourced from the shared App-Group config so every
    /// snooze surface agrees (code review #1). M7 Settings writes it (§16/D6); until
    /// then it falls back to BadgerConfig.fallbackSnoozeMinutes.
    private var defaultSnooze: TimeInterval { BadgerConfig.defaultSnoozeDuration }

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
        let engine = BadgerEngine(container: container, registry: registry,
                                  liveActivity: LiveActivityController())
        self.engine = engine
        // L11/§11: register the shared engine so in-app intents (the alarm's "I did it"
        // secondary button, MarkBadgerDoneIntent) resolve it via @Dependency.
        AppDependencyManager.shared.add(dependency: engine)
        super.init()
    }

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions:
                        [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiSeed") {
            BadgerConfig.hasCompletedOnboarding = true   // land on the console for P4 screenshots
        }
        #endif
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([BadgerNotifications.category()])
        // Auth is requested with rationale by the M7/§17 onboarding flow (OnboardingView), not
        // fire-and-forget here — so the system prompts appear with context on first launch.
        // Rehydrate the AlarmKit owner map from persisted armedAlarms BEFORE observing, so a
        // prior-process alarm firing is attributed after a relaunch (M3 cold-kill fix, ckpt 4).
        Task { @MainActor in
            engine.seedBuiltInLadders()       // D10 built-in ladder presets (idempotent) — M7 CP2
            await engine.rehydrateArmedAlarms()
            await engine.sweepStrayAlerts()   // cancel crash-window orphans no live Badger owns (M6 CP2)
            await refreshFocusFilter()        // apply the active Focus's escalation cap on launch (M6 CP4)
            engine.startObserving()   // consume AlarmKit's live lifecycle stream (§14 path 1)
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-uiSeed") { await Self.seedSampleBadgers(engine) }
            #endif
        }
        return true
    }

    /// Read the active Focus's BadgerMe filter (if any) and apply it (§13, M6 CP4). `.current`
    /// throws when the active Focus has no BadgerMe filter → nil → the filter clears, so a stale
    /// cap never outlives its Focus. Live Focus changes are handled by the filter intent's
    /// headless perform() (SP14); this is the cold-launch backstop.
    func refreshFocusFilter() async {
        let current = try? await SetBadgerFocusFilterIntent.current
        await engine.applyFocusFilter(cap: current?.cap?.prominenceCap, onlyTag: current?.onlyTag)
    }

    #if DEBUG
    /// P4 design-review seed (gated by the -uiSeed launch arg): a spread of Badgers across the
    /// escalation heat range so a single screenshot shows calm → warm → hot → muted.
    static func seedSampleBadgers(_ engine: BadgerEngine) async {
        let now = Date()
        let ladder = ContentView.devNotificationLadder      // rungs @ +10 / +25 / +45s
        await engine.create(title: "Call the dentist", startAt: now,
                            rungs: ladder, maxSnoozeCount: 1)                        // pending → calm
        await engine.create(title: "Send the invoice", startAt: now.addingTimeInterval(-30),
                            rungs: ladder, maxSnoozeCount: 1)                        // level 1 → warm
        await engine.create(title: "Take the meds", startAt: now.addingTimeInterval(-100),
                            rungs: ladder, maxSnoozeCount: 1)                        // last rung → hot
        let snoozed = await engine.create(title: "Water the plants", startAt: now,
                                          rungs: ladder, maxSnoozeCount: 1)
        await engine.snooze(snoozed, duration: 3600)                                // → muted
        await engine.reconcileAll()
    }
    #endif

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
        // Swiping a notification away is non-resolving (§14) and needs no catch-up — a later
        // foreground reconcile handles that. Acting on it would log a redundant reconcile (the
        // second of the two duplicate events seen on device).
        if response.actionIdentifier == UNNotificationDismissActionIdentifier { return }
        await engine.handleNotificationResponse(badgerID: id,
                                                actionID: response.actionIdentifier,
                                                defaultSnooze: defaultSnooze)
    }
}
