//
//  AlarmKitChannel.swift
//  BadgerKit — the `alarmkit` AlertChannel (Phase 5 §9/§10), hard/breakthrough rungs.
//
//  AlarmKit-backed. Unlike notifications, alarms pierce silent + Focus (L6) and are
//  observable at fire via `AlarmManager.alarmUpdates` (§14 path 1). Guarded by
//  `#if canImport(AlarmKit)` + `@available(iOS 26.1, *)` so the package still compiles
//  on macOS for `swift test`; the engine talks to this only through AlertChannel and
//  never imports AlarmKit itself.
//
//  SDK facts (verified against the iOS 26.5 .swiftinterface, 2026-07-07):
//   - AlarmConfiguration.stopIntent/secondaryIntent are `(any LiveActivityIntent)?`, so
//     Stop and resolve buttons are handled by in-app intents.
//     secondaryButtonBehavior: .custom routes taps to it. The system Stop is a slider
//     (the 26.1 `stopButton` init is deprecated).
//   - A snapshot `Alarm` carries only id/schedule/countdownDuration/state — NO metadata.
//     So observe()/cancelAll can't read the owning Badger off the snapshot; the channel
//     keeps its own [alarmID: (badgerID, slot)] map, built at schedule() time.
//   - Alarm.State is {scheduled, countdown, paused, alerting}; no terminal case, so a
//     stopped/resolved alarm just leaves the `alarms` array (removal = dismissal).
//   - Rungs fire at absolute instants, so we schedule Alarm.Schedule.fixed(Date) rather
//     than a countdown timer (arm-ahead; no live app needed to start a countdown).
//   - Sound is ActivityKit's AlertConfiguration.AlertSound (.default / .named).
//
//  Known M3 limitation (closed in M6/§14): the id→badger map is in-memory, so after a
//  cold kill it is empty and cancelAll can't reach alarms armed in a prior process.
//  Reconcile-on-foreground (path 3) re-derives state from persisted startAt/delays and
//  re-arms; full cold-kill teardown of straggler alarms is an M6 reconcile concern. The
//  live (app-running) path is fully covered here.
//

import Foundation

#if canImport(AlarmKit)
import AlarmKit
import ActivityKit
import AppIntents
import SwiftUI

/// Serialized with the alarm's Live Activity, so keep it tiny and reference big data by
/// id (§12). `nonisolated` so it satisfies AlarmMetadata (Sendable) even under Xcode 26's
/// default @MainActor type isolation.
@available(iOS 26.1, *)
public nonisolated struct BadgerAlarmMetadata: AlarmMetadata {
    public let badgerID: UUID
    public let rung: Int
    public init(badgerID: UUID, rung: Int) {
        self.badgerID = badgerID
        self.rung = rung
    }
}

@available(iOS 26.1, *)
public actor AlarmKitChannel: AlertChannel {
    public nonisolated let id = "alarmkit"
    public nonisolated let capabilities = ChannelCapabilities(
        prominences: [.breakthrough],
        deliversInBackground: true,
        observableAtFire: true,
        needsWidget: true,
        supportsArbitraryRecurrence: false)   // SP3: AlarmKit recurrence is weekly wall-clock only

    /// alarmID → (badgerID, slot), built at schedule() so observe()/cancelAll recover the
    /// identity a snapshot Alarm doesn't carry.
    private var owners: [UUID: (badgerID: UUID, slot: ScheduleSlot)] = [:]
    /// Last-seen per-alarm alerting state, used to diff app-global snapshots.
    private var lastAlerting: [UUID: Bool] = [:]

    public init() {}

    public func schedule(_ action: ChannelAction, at fireDate: Date,
                         recurrence: ChannelRecurrence?, badgerID: UUID,
                         slot: ScheduleSlot) async throws -> ScheduledRef {
        let rung = rungIndex(of: slot)
        let alarmID = UUID()

        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: action.message ?? "BadgerMe"),
            secondaryButton: AlarmButton(text: "I did it", textColor: .white,
                                         systemImageName: "checkmark"),
            secondaryButtonBehavior: .custom)
        let attributes = AlarmAttributes(
            presentation: AlarmPresentation(alert: alert),
            metadata: BadgerAlarmMetadata(badgerID: badgerID, rung: rung),
            tintColor: .red)
        let config = AlarmManager.AlarmConfiguration(
            schedule: .fixed(fireDate),
            attributes: attributes,
            stopIntent: MarkBadgerDismissedIntent(badgerID: badgerID, rung: rungIndex(of: slot)),
            secondaryIntent: MarkBadgerDoneIntent(badgerID: badgerID),
            sound: sound(for: action.soundRef))

        _ = try await AlarmManager.shared.schedule(id: alarmID, configuration: config)
        owners[alarmID] = (badgerID, slot)
        return ScheduledRef(channelID: id, identifier: alarmID.uuidString, slot: slot)
    }

    public func cancel(_ ref: ScheduledRef) async {
        guard let alarmID = UUID(uuidString: ref.identifier) else { return }
        try? AlarmManager.shared.cancel(id: alarmID)
        owners[alarmID] = nil
        lastAlerting[alarmID] = nil
    }

    public func cancelAll(forBadgerID badgerID: UUID) async {
        let mine = owners.filter { $0.value.badgerID == badgerID }.map(\.key)
        for alarmID in mine {
            try? AlarmManager.shared.cancel(id: alarmID)
            owners[alarmID] = nil
            lastAlerting[alarmID] = nil
        }
    }

    /// Cancel by explicit alarm ids (from the persisted `armedAlarms`). Works with an
    /// EMPTY owners map — after a cold kill in a fresh process — which is the whole point
    /// (M3 cold-kill fix). `AlarmManager.cancel` is best-effort, so a gone id is harmless.
    public func cancel(identifiers: [String]) async {
        for identifier in identifiers {
            guard let alarmID = UUID(uuidString: identifier) else { continue }
            try? AlarmManager.shared.cancel(id: alarmID)
            owners[alarmID] = nil
            lastAlerting[alarmID] = nil
        }
    }

    /// Rebuild the owner map from persisted armed refs after a relaunch, so a firing of an
    /// alarm armed in a prior process is attributed to its Badger by `observe()`.
    /// `lastAlerting` is left unseeded (defaults to not-alerting) so the first snapshot
    /// showing the alarm alerting emits its fire.
    public func adopt(badgerID: UUID, refs: [ArmedRef]) async {
        for ref in refs {
            guard let alarmID = UUID(uuidString: ref.id) else { continue }
            owners[alarmID] = (badgerID, ref.slot)
        }
    }

    /// App-global enumerate for the CP2 stray sweep: every alarm id this app currently has
    /// scheduled. SDK-verified 2026-07-17 against the 26.5 .swiftinterface — `AlarmManager.alarms`
    /// is a throwing pull getter (no need to snapshot the `alarmUpdates` stream) and `Alarm.id` is
    /// the UUID we scheduled with. App-scoped by the system, so this is exactly the set the sweep
    /// diffs against live Badgers' `armedAlarms`.
    public func scheduledIdentifiers() async -> [String] {
        let alarms = (try? AlarmManager.shared.alarms) ?? []
        return alarms.map(\.id.uuidString)
    }

    #if DEBUG
    /// Diagnostic (SP9/B1): arm minimal far-future alarms until the per-app limit throws,
    /// report the count reached, then cancel them all. Throwaway dev instrumentation —
    /// never used in production paths. Reuses `schedule`/`cancel`, so no config drift.
    public func probeCeiling(maxTries: Int = 512) async -> Int {
        let action = ChannelAction(channelID: id, prominence: .breakthrough)
        let far = Date().addingTimeInterval(3600)
        var refs: [ScheduledRef] = []
        while refs.count < maxTries {
            do {
                let ref = try await schedule(action, at: far, recurrence: nil,
                                             badgerID: UUID(), slot: .rung(0))
                refs.append(ref)
            } catch {
                break
            }
        }
        let count = refs.count
        for ref in refs { await cancel(ref) }
        return count
    }
    #endif

    public nonisolated func observe() -> AsyncStream<ChannelEvent>? {
        AsyncStream { continuation in
            let task = Task {
                for await snapshot in AlarmManager.shared.alarmUpdates {
                    for event in await self.diff(snapshot) { continuation.yield(event) }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Diffing

    /// Compare an app-global snapshot against last-known state and emit transitions for
    /// owned alarms. Entering `.alerting` => the rung fired; disappearing from the
    /// snapshot => a bare removal (dismissal, non-resolving, §8).
    private func diff(_ snapshot: [Alarm]) -> [ChannelEvent] {
        let entries = snapshot.map { AlarmSnapshotEntry(id: $0.id, isAlerting: $0.state == .alerting) }
        let diff = diffAlarmSnapshot(entries: entries, owners: owners, lastAlerting: lastAlerting)
        lastAlerting = diff.newLastAlerting
        for removedID in diff.removedOwners {
            owners[removedID] = nil
            lastAlerting[removedID] = nil
        }
        return diff.events
    }

    // MARK: - Mapping

    private func rungIndex(of slot: ScheduleSlot) -> Int {
        switch slot {
        case .rung(let k):             return k
        case .repeatTail(let rung, _): return rung
        case .wake:                    return -1
        }
    }

    private nonisolated func sound(for ref: SoundRef?) -> AlertConfiguration.AlertSound {
        switch ref {
        case .none:            return .default
        case .builtIn:         return .default        // curated catalog is M7/D10
        case .imported(let f): return .named(f)       // bundle or Library/Sounds (§20)
        case .renderedSpeech:  return .default        // D11 fast-follow
        }
    }
}
#endif
