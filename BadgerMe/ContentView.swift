//
//  ContentView.swift
//  BadgerMe — thin console (§16). The real UI is M7; this is a minimal list plus a
//  DEBUG dev/diagnostics harness so escalation can be exercised AND observed on device
//  before the App Intents readout (M4) and the history timeline (M7) exist. The
//  diagnostics section exists to run device-verify Tiers B/C (log readout + probe
//  buttons) and is throwaway — it is not the M7 console. Everything calls the shared engine.
//

import SwiftUI
import SwiftData
import BadgerKit

struct ContentView: View {
    let engine: BadgerEngine
    /// DEBUG diagnostic (SP9/B1): probe the per-app AlarmKit alarm ceiling. nil in release
    /// or if AlarmKit is unavailable. Wired by the composition root.
    var probeCeiling: (@Sendable () async -> Int)? = nil

    @Query(sort: \Badger.createdAt, order: .reverse) private var badgers: [Badger]
    #if DEBUG
    @Query(sort: \EventRecord.timestamp, order: .reverse) private var events: [EventRecord]
    @State private var ceilingResult: String?
    #endif

    var body: some View {
        NavigationStack {
            List {
                #if DEBUG
                Section("Dev harness (M3 · device-verify)") {
                    Button("New Badger — 10/25/45s notification ladder") {
                        Task { await engine.create(title: "Test Badger", startAt: .now,
                                                    rungs: Self.devNotificationLadder, maxSnoozeCount: 1) }
                    }
                    Button("New Badger — 10/25/45s breakthrough ladder") {
                        Task { await engine.create(title: "AlarmKit Test Badger", startAt: .now,
                                                    rungs: Self.devBreakthroughLadder, maxSnoozeCount: 1) }
                    }
                    Button("Reconcile all (catch up)") { Task { await engine.reconcileAll() } }
                }

                Section("Diagnostics (Tier B)") {
                    // B1 / SP9 — arm minimal alarms until the per-app limit throws; the probe
                    // cancels them all and reports the count.
                    Button("Probe alarm ceiling (B1 / SP9)") {
                        Task {
                            ceilingResult = "probing…"
                            if let probe = probeCeiling {
                                let n = await probe()
                                ceilingResult = "ceiling ≈ \(n) alarms"
                            } else {
                                ceilingResult = "unavailable (no AlarmKit)"
                            }
                        }
                    }
                    if let ceilingResult {
                        Text(ceilingResult).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                    // B2 / SP13 — single-rung breakthrough Badgers at short leads; note which
                    // FIRST fire lands on time. (Single-rung ladders self-repeat at their delay,
                    // so mark each Done after the first fire.)
                    Button("Near-future probe — alarms @ 5 / 15 / 30s (B2 / SP13)") {
                        Task {
                            for t: TimeInterval in [5, 15, 30] {
                                await engine.create(
                                    title: "NF \(Int(t))s", startAt: .now,
                                    rungs: [RungSpec(index: 0, delay: t,
                                                     actions: [ChannelAction(channelID: "alarmkit",
                                                                             prominence: .breakthrough)])],
                                    maxSnoozeCount: 1)
                            }
                        }
                    }
                }
                #endif

                Section("Badgers") {
                    if badgers.isEmpty {
                        Text("No Badgers yet.").foregroundStyle(.secondary)
                    }
                    ForEach(badgers) { BadgerRow(badger: $0, engine: engine) }
                }

                #if DEBUG
                Section("Event log (newest first)") {
                    if events.isEmpty {
                        Text("No events yet.").foregroundStyle(.secondary)
                    }
                    ForEach(events.prefix(25)) { EventRow(event: $0) }
                }
                #endif
            }
            .navigationTitle("BadgerMe")
        }
        .task { await engine.reconcileAll() }   // catch up whenever the console appears
    }

    #if DEBUG
    static var devNotificationLadder: [RungSpec] {
        [
            RungSpec(index: 0, delay: 10, actions: [ChannelAction(channelID: "notification", prominence: .active)]),
            RungSpec(index: 1, delay: 25, actions: [ChannelAction(channelID: "notification", prominence: .timeSensitive)]),
            RungSpec(index: 2, delay: 45, actions: [ChannelAction(channelID: "notification", prominence: .timeSensitive)]),
        ]
    }

    static var devBreakthroughLadder: [RungSpec] {
        [
            RungSpec(index: 0, delay: 10, actions: [ChannelAction(channelID: "alarmkit", prominence: .breakthrough)]),
            RungSpec(index: 1, delay: 25, actions: [ChannelAction(channelID: "alarmkit", prominence: .breakthrough)]),
            RungSpec(index: 2, delay: 45, actions: [ChannelAction(channelID: "alarmkit", prominence: .breakthrough)]),
        ]
    }
    #endif
}

private struct BadgerRow: View {
    let badger: Badger
    let engine: BadgerEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(badger.title).font(.headline)
            Text(statusText).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("Done") { Task { await engine.markDone(badger.id) } }
                Button("Snooze 1m") { Task { await engine.snooze(badger.id, duration: 60) } }
                Button("Stop") { Task { await engine.stop(badger.id) } }
                Button("Delete", role: .destructive) { Task { await engine.delete(badger.id) } }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .font(.caption)
        }
        .padding(.vertical, 2)
    }

    private var statusText: String {
        let armed = "· \(badger.armedAlarms.count) armed"
        switch badger.state {
        case .pending: return "pending \(armed)"
        case .active:  return "active · level \(badger.currentLevel) \(armed)"
        case .snoozed:
            let t = badger.snoozeUntil?.formatted(date: .omitted, time: .shortened) ?? "—"
            return "snoozed until \(t) \(armed)"
        case .done:    return "done"
        case .stopped: return "stopped"
        }
    }
}

#if DEBUG
private struct EventRow: View {
    let event: EventRecord

    var body: some View {
        HStack(spacing: 8) {
            Text(event.timestamp.formatted(date: .omitted, time: .standard))
                .font(.caption2.monospaced()).foregroundStyle(.secondary)
            Text(event.kindRaw + (event.level.map { " L\($0)" } ?? ""))
                .font(.caption.monospaced())
            Spacer()
            Text(event.badgerID.uuidString.prefix(4) + " · " + event.sourceRaw)
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }
}
#endif
