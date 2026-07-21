//
//  BadgerMeApp.swift
//  BadgerMe
//
//  Thin shell (L3): the SwiftUI app is one client of the shared engine/container that
//  the AppDelegate composition root builds. It holds no escalation logic.
//

import SwiftUI
import SwiftData
import BadgerKit

@main
struct BadgerMeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            RootView(engine: appDelegate.engine, probeCeiling: appDelegate.debugProbeCeiling)
            #else
            RootView(engine: appDelegate.engine)
            #endif
        }
        // Same container the engine writes to, so @Query reflects engine saves live.
        .modelContainer(appDelegate.container)
    }
}

/// Gates first-launch permission onboarding (§17) in front of the console, and owns the shared
/// `Permissions` model that onboarding and Settings both drive.
struct RootView: View {
    let engine: BadgerEngine
    var probeCeiling: (@Sendable () async -> Int)? = nil

    @State private var permissions = Permissions()
    @State private var onboarded = BadgerConfig.hasCompletedOnboarding

    var body: some View {
        Group {
            if onboarded {
                #if DEBUG
                ContentView(engine: engine, permissions: permissions, probeCeiling: probeCeiling)
                #else
                ContentView(engine: engine, permissions: permissions)
                #endif
            } else {
                OnboardingView(permissions: permissions) {
                    BadgerConfig.hasCompletedOnboarding = true
                    onboarded = true
                }
            }
        }
        .task { await permissions.refresh() }
    }
}
