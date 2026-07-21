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

    // MARK: - Default ladder (M7 CP2 / D10)

    private static let defaultLadderKey = "defaultLadderID"

    /// The ladder a new Badger uses when the caller names none (create's fallback, §16). Defaults
    /// to the built-in "Default" preset until Settings writes another. Stored as a UUID string.
    public static var defaultLadderID: UUID {
        get {
            guard let s = store?.string(forKey: defaultLadderKey), let id = UUID(uuidString: s)
            else { return LadderPresets.defaultID }
            return id
        }
        set { store?.set(newValue.uuidString, forKey: defaultLadderKey) }
    }

    // MARK: - Snooze-duration options (M7 CP2 / D6)

    private static let snoozeOptionsKey = "snoozeOptionsMinutes"

    /// The quick-snooze menu (minutes) until Settings writes one (§16/D6).
    public static let fallbackSnoozeOptions = [5, 9, 15, 30, 60]

    /// Positive, de-duplicated, sorted; empty falls back to `fallbackSnoozeOptions`. Shared by the
    /// getter (sanitising stored values) and setter (sanitising before store) so both agree.
    public static func sanitizedSnoozeOptions(_ raw: [Int]) -> [Int] {
        let clean = Array(Set(raw.filter { $0 > 0 })).sorted()
        return clean.isEmpty ? fallbackSnoozeOptions : clean
    }

    /// The quick-snooze durations (minutes) the UI offers. Written by M7 Settings.
    public static var snoozeOptionsMinutes: [Int] {
        get { sanitizedSnoozeOptions((store?.array(forKey: snoozeOptionsKey) as? [Int]) ?? []) }
        set { store?.set(sanitizedSnoozeOptions(newValue), forKey: snoozeOptionsKey) }
    }

    // MARK: - Concurrency cap (M7 CP3 / D3)

    /// Max concurrently-escalating (non-terminal) Badgers (D3). Set to the measured **foreground
    /// Live Activity concurrent ceiling (5, CP6 device probe)** so every escalating Badger keeps its
    /// own ambient card (§12) — a 6th would silently fail `Activity.request` and escalate without a
    /// card. The 64-pending-notification budget is the other bound (looser; mitigated by
    /// reconcile-replenish). The console blocks new activations at this count. D1 hybrid-overflow
    /// (collapse the extras into one summary activity) would allow more and is a post-v1 option.
    public static let maxConcurrentEscalating = 5

    // MARK: - Onboarding (M7 CP5)

    private static let onboardedKey = "hasCompletedOnboarding"

    /// Whether the first-launch permission onboarding has been completed (§17). Set once the flow
    /// finishes; gates whether the app shows onboarding or the console.
    public static var hasCompletedOnboarding: Bool {
        get { store?.bool(forKey: onboardedKey) ?? false }
        set { store?.set(newValue, forKey: onboardedKey) }
    }
}
