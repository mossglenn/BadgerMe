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
//   - AlarmConfiguration.secondaryIntent is `(any LiveActivityIntent)?`, so the resolve
//     button is a LiveActivityIntent (MarkBadgerDoneIntent), run in-app.
//     secondaryButtonBehavior: .custom routes taps to it. The system Stop is a slider
//     (the 26.1 `stopButton` init is deprecated) — a stop is a bare removal, surfaced by
//     observe() as .dismissed (non-resolving, §8).
//   - A snapshot `Alarm` carries only id/schedule/countdownDuration/state — NO metadata.
//     So observe()/cancelAll can't read the owning Badger off the snapshot; the channel
//     keeps its own [alarmID: (badgerID, rung)] map, built at schedule() time.
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
nonisolated struct BadgerAlarmMetadata: AlarmMetadata {
    let badgerID: UUID
    let rung: Int
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

    /// alarmID → (badgerID, rung), built at schedule() so observe()/cancelAll recover the
    /// identity a snapshot Alarm doesn't carry.
    private var owners: [UUID: (badgerID: UUID, rung: Int)] = [:]
    /// Last-seen per-alarm state, to diff each app-global snapshot into transitions.
    private var lastStates: [UUID: Alarm.State] = [:]

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
            secondaryIntent: MarkBadgerDoneIntent(badgerID: badgerID.uuidString),
            sound: sound(for: action.soundRef))

        _ = try await AlarmManager.shared.schedule(id: alarmID, configuration: config)
        owners[alarmID] = (badgerID, rung)
        return ScheduledRef(channelID: id, identifier: alarmID.uuidString, slot: slot)
    }

    public func cancel(_ ref: ScheduledRef) async {
        guard let alarmID = UUID(uuidString: ref.identifier) else { return }
        try? AlarmManager.shared.cancel(id: alarmID)
        owners[alarmID] = nil
        lastStates[alarmID] = nil
    }

    public func cancelAll(forBadgerID badgerID: UUID) async {
        let mine = owners.filter { $0.value.badgerID == badgerID }.map(\.key)
        for alarmID in mine {
            try? AlarmManager.shared.cancel(id: alarmID)
            owners[alarmID] = nil
            lastStates[alarmID] = nil
        }
    }

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
        var events: [ChannelEvent] = []
        let present = Set(snapshot.map(\.id))

        for alarm in snapshot {
            guard let owner = owners[alarm.id] else { continue }
            let prior = lastStates[alarm.id]
            if alarm.state == .alerting, prior != .alerting {
                events.append(.levelFired(badgerID: owner.badgerID, rung: owner.rung))
            }
            lastStates[alarm.id] = alarm.state
        }

        for (alarmID, owner) in owners where !present.contains(alarmID) {
            events.append(.dismissed(badgerID: owner.badgerID, rung: owner.rung))
            owners[alarmID] = nil
            lastStates[alarmID] = nil
        }
        return events
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
