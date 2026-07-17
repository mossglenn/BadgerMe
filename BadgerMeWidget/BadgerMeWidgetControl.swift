//
//  BadgerMeWidgetControl.swift
//  BadgerMeWidget — a Control Center control: "Snooze all" (§11, M6 CP3).
//
//  One-tap snooze of every actively-escalating Badger, backed by SnoozeAllBadgersIntent
//  (runs in-app headless, background-launched from the control). A "New Badger" control is
//  deferred to M7, when the create screen it would open exists.
//

import AppIntents
import SwiftUI
import WidgetKit
import BadgerKit

struct BadgerMeWidgetControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.badgerme.BadgerMe.SnoozeAll") {
            ControlWidgetButton(action: SnoozeAllBadgersIntent()) {
                Label("Snooze all Badgers", systemImage: "moon.zzz.fill")
            }
        }
        .displayName("Snooze All Badgers")
        .description("Snooze every actively escalating Badger.")
    }
}
