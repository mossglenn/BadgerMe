//
//  BadgerConfig.swift
//  BadgerKit — shared, App-Group-backed settings the app and widget both read.
//
//  Single source of truth for app-wide preferences more than one process/surface needs
//  (code review #1). v1 carries only the default snooze duration: it lives in the shared
//  App-Group UserDefaults so every snooze surface — the notification action (AppDelegate),
//  the Live-Activity button (widget), and the Shortcuts convenience init — resolves the
//  same number instead of hardcoding its own. M7 Settings (§16/D6) writes it; until then
//  reads fall back to `fallbackSnoozeMinutes`.
//
//  Foundation-only (no #if os(iOS) guard): a plain UserDefaults suite, so it compiles on
//  macOS and `swift test` links it. On the macOS test host the suite is unshared and the
//  key unset, so reads return the fallback — no test depends on the stored value.
//

import Foundation

public enum BadgerConfig {
    /// The App Group both targets share (§4/§17); matches the ModelContainer's suite.
    public static let appGroupID = "group.com.badgerme.shared"

    /// Fallback until Settings writes one (M7/D6). 9 minutes is the app-wide default the
    /// notification path already used (and iOS's classic snooze); the widget's stray 15
    /// was consolidated onto it. Change this one constant to move the default before M7.
    public static let fallbackSnoozeMinutes = 9

    private static let snoozeMinutesKey = "defaultSnoozeMinutes"

    private static var store: UserDefaults? { UserDefaults(suiteName: appGroupID) }

    /// App-wide default snooze, in minutes. Read by every snooze surface; written by M7
    /// Settings. Falls back to `fallbackSnoozeMinutes` when unset or non-positive.
    public static var defaultSnoozeMinutes: Int {
        let stored = store?.integer(forKey: snoozeMinutesKey) ?? 0
        return stored > 0 ? stored : fallbackSnoozeMinutes
    }

    /// The same value as a `TimeInterval` (seconds) for the engine's `snooze(_:duration:)`.
    public static var defaultSnoozeDuration: TimeInterval {
        TimeInterval(defaultSnoozeMinutes * 60)
    }

    /// Persist a new app-wide default (M7 Settings). Clamped to at least one minute.
    public static func setDefaultSnoozeMinutes(_ minutes: Int) {
        store?.set(max(1, minutes), forKey: snoozeMinutesKey)
    }
}
