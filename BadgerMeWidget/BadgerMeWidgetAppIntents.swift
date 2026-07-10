//
//  BadgerMeWidgetAppIntents.swift
//  BadgerMeWidget (extension target) — opts BadgerKit's App Intents into the widget
//  process's metadata so intents run in-extension (the SP10 / app-killed path, M4).
//
//  Mirror of the app-target conformer: the widget is a separate process that runs
//  interactive-widget / Live-Activity / control intents, so it needs its own
//  AppIntentsPackage linkage to the package.
//

import AppIntents
import BadgerKit

struct BadgerMeWidgetAppIntentsPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [BadgerKitPackage.self] }
}
