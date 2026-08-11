//
//  DeveloperView.swift
//  BadgerMe — DEBUG-only device-verify harness, relocated off the home page (previously
//  ContentView's "Dev harness" section). Reachable via Settings ▸ Developer. Never ships:
//  the whole file is behind #if DEBUG.
//

#if DEBUG
import SwiftUI
import SwiftData
import BadgerKit

struct DeveloperView: View {
    let engine: BadgerEngine
    var probeCeiling: (@Sendable () async -> Int)? = nil
    @State private var ceilingResult: String?
    @Query(sort: \EventRecord.timestamp, order: .reverse) private var events: [EventRecord]

    var body: some View {
        List {
            Section("Create test Badgers") {
                Button("New Badger — 10/25/45s notification ladder") {
                    Task { await engine.create(title: "Test Badger", startAt: .now,
                                                rungs: ContentView.devNotificationLadder, maxSnoozeCount: 1) }
                }
                Button("New Badger — 10/25/45s breakthrough ladder") {
                    Task { await engine.create(title: "AlarmKit Test Badger", startAt: .now,
                                                rungs: ContentView.devBreakthroughLadder, maxSnoozeCount: 1) }
                }
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

            Section("Diagnostics") {
                Button("Reconcile all (catch up)") { Task { await engine.reconcileAll() } }
                Button("Probe alarm ceiling (B1 / SP9)") {
                    Task {
                        ceilingResult = "probing…"
                        if let probe = probeCeiling {
                            ceilingResult = "ceiling ≈ \(await probe()) alarms"
                        } else {
                            ceilingResult = "unavailable (no AlarmKit)"
                        }
                    }
                }
                Button("Probe Live Activity ceiling (D1 / D3)") {
                    Task {
                        ceilingResult = "probing LA…"
                        ceilingResult = await LAProbe.measureCeiling()
                    }
                }
                if let ceilingResult {
                    Text(ceilingResult).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            }

            Section("Event log (newest first)") {
                if events.isEmpty {
                    Text("No events yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(events.prefix(25)) { event in
                        Text(event.timestamp.formatted(date: .omitted, time: .standard)
                             + "  " + event.kindRaw + (event.level.map { " L\($0)" } ?? ""))
                            .font(.caption2.monospaced())
                    }
                }
            }
        }
        .navigationTitle("Developer")
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
