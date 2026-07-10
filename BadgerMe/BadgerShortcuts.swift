//
//  BadgerShortcuts.swift
//  BadgerMe (app target) — zero-config App Shortcuts (M4, §11).
//
//  Surfaces core intents to Spotlight / Shortcuts / Siri with spoken phrases (each must
//  include the app name via \(.applicationName)). The intents live in BadgerKit and are
//  discoverable via the AppIntentsPackage linkage; this provider is app-target code.
//  Parameterised actions (mark done) omit the parameter in the phrase so Siri resolves
//  the Badger through BadgerQuery (active suggestions) at invocation.
//

import AppIntents
import BadgerKit

struct BadgerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateBadgerIntent(),
            phrases: [
                "Create a Badger with \(.applicationName)",
                "Badger me with \(.applicationName)",
            ],
            shortTitle: "Create Badger",
            systemImageName: "bell.badge")

        AppShortcut(
            intent: GetActiveBadgersIntent(),
            phrases: [
                "What's badgering me in \(.applicationName)",
                "What's badgering me with \(.applicationName)",
            ],
            shortTitle: "Active Badgers",
            systemImageName: "list.bullet")

        AppShortcut(
            intent: MarkBadgerDoneIntent(),
            phrases: [
                "Mark a Badger done in \(.applicationName)",
                "I did it with \(.applicationName)",
            ],
            shortTitle: "Mark Done",
            systemImageName: "checkmark.circle")
    }
}
