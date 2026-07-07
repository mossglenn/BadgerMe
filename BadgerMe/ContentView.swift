//
//  ContentView.swift
//  BadgerMe — thin console (§16). The real UI is M7; this is a minimal list plus a
//  DEBUG dev harness so soft-rung escalation can be exercised end-to-end on device
//  before the App Intents surface (M4) exists. Everything calls the shared engine.
//

import SwiftUI
import SwiftData
import BadgerKit

struct ContentView: View {
    let engine: BadgerEngine
    @Query(sort: \Badger.createdAt, order: .reverse) private var badgers: [Badger]

    var body: some View {
        NavigationStack {
            List {
                #if DEBUG
                Section("Dev harness (M2)") {
                    Button("New test Badger — 10s / 25s / 45s notification ladder") {
                        Task {
                            await engine.create(title: "Test Badger", startAt: .now,
                                                rungs: Self.devLadder, maxSnoozeCount: 1)
                        }
                    }
                    Button("Reconcile all (catch up)") { Task { await engine.reconcileAll() } }
                }
                #endif

                Section("Badgers") {
                    if badgers.isEmpty {
                        Text("No Badgers yet.").foregroundStyle(.secondary)
                    }
                    ForEach(badgers) { BadgerRow(badger: $0, engine: engine) }
                }
            }
            .navigationTitle("BadgerMe")
        }
        .task { await engine.reconcileAll() }   // catch up whenever the console appears
    }

    #if DEBUG
    static var devLadder: [RungSpec] {
        [
            RungSpec(index: 0, delay: 10, actions: [ChannelAction(channelID: "notification", prominence: .active)]),
            RungSpec(index: 1, delay: 25, actions: [ChannelAction(channelID: "notification", prominence: .timeSensitive)]),
            RungSpec(index: 2, delay: 45, actions: [ChannelAction(channelID: "notification", prominence: .timeSensitive)]),
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
        switch badger.state {
        case .pending: return "pending"
        case .active:  return "active · level \(badger.currentLevel)"
        case .snoozed:
            let t = badger.snoozeUntil?.formatted(date: .omitted, time: .shortened) ?? "—"
            return "snoozed until \(t)"
        case .done:    return "done"
        case .stopped: return "stopped"
        }
    }
}
