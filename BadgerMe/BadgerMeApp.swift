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
            ContentView(engine: appDelegate.engine, probeCeiling: appDelegate.debugProbeCeiling)
            #else
            ContentView(engine: appDelegate.engine)
            #endif
        }
        // Same container the engine writes to, so @Query reflects engine saves live.
        .modelContainer(appDelegate.container)
    }
}
