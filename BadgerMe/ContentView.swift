//
//  ContentView.swift
//  BadgerMe — the console root: the release Badger list (§16, M7 CP3). Reads via @Query on the
//  @Model types (main-actor); every mutation dispatches through the shared engine (L3). The DEBUG
//  dev/diagnostics harness is retained behind #if DEBUG for device-verify work.
//

import SwiftUI
import SwiftData
import BadgerKit

struct ContentView: View {
    let engine: BadgerEngine
    let permissions: Permissions
    /// DEBUG diagnostic (SP9/B1): probe the per-app AlarmKit alarm ceiling. nil in release.
    var probeCeiling: (@Sendable () async -> Int)? = nil

    @Query(sort: \Badger.createdAt, order: .reverse) private var badgers: [Badger]
    @State private var showCreate = false
    @State private var showSettings = false
    #if DEBUG
    @Query(sort: \EventRecord.timestamp, order: .reverse) private var events: [EventRecord]
    @State private var ceilingResult: String?
    #endif

    private var escalatingCount: Int { badgers.filter { !$0.isTerminal }.count }
    private var atCap: Bool { escalatingCount >= BadgerConfig.maxConcurrentEscalating }

    var body: some View {
        NavigationStack {
            List {
                if badgers.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing's badgering you", systemImage: "pawprint")
                    } description: {
                        Text("Add a Badger and it'll keep after you about something you'd otherwise let slide.")
                            .font(.badgerVoice(.callout))
                    } actions: {
                        Button { Haptics.impact(.light); showCreate = true } label: {
                            Label("New Badger", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DesignTokens.accent)
                    }
                } else {
                    Section {
                        ForEach(badgers) { badger in
                            NavigationLink {
                                BadgerDetailView(badger: badger, engine: engine)
                            } label: {
                                BadgerRow(badger: badger)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: !badger.isTerminal) {
                                if !badger.isTerminal {
                                    Button { Haptics.success(); Task { await engine.markDone(badger.id) } } label: {
                                        Label("Done", systemImage: "checkmark.circle.fill")
                                    }.tint(DesignTokens.positive)
                                }
                            }
                            .swipeActions(edge: .leading) {
                                if !badger.isTerminal && badger.state != .snoozed {
                                    Button { Haptics.impact(.light); Task { await engine.snooze(badger.id, duration: BadgerConfig.defaultSnoozeDuration) } } label: {
                                        Label("Snooze", systemImage: "moon.zzz.fill")
                                    }.tint(DesignTokens.accent)
                                }
                            }
                        }
                    } footer: {
                        if atCap { capFooter }
                    }
                }
                #if DEBUG
                debugHarness
                eventLogSection
                #endif
            }
            .navigationTitle("BadgerMe")
            .safeAreaInset(edge: .bottom) {
                if !badgers.isEmpty { newBadgerButton }
            }
            .refreshable { await engine.reconcileAll() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showCreate) { CreateBadgerView(engine: engine) }
            .sheet(isPresented: $showSettings) { SettingsView(engine: engine, permissions: permissions) }
        }
        .task { await engine.reconcileAll() }
    }

    private var capFooter: some View {
        Label("Paws are full — resolve one to add another (\(BadgerConfig.maxConcurrentEscalating) max).",
              systemImage: "pawprint.fill")
            .font(.footnote)
    }

    private var newBadgerButton: some View {
        Button {
            Haptics.impact(.light)
            showCreate = true
        } label: {
            Label("New Badger", systemImage: "plus")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.xs)
        }
        .buttonStyle(.borderedProminent)
        .tint(DesignTokens.accent)
        .disabled(atCap)
        .padding(.horizontal, Space.screenMargin)
        .padding(.bottom, Space.xs)
        .accessibilityLabel("New Badger")
    }
}

private struct BadgerRow: View {
    let badger: Badger
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: badger.identityIcon)
                .imageScale(.medium)
                .foregroundStyle(badger.escalationColor)
                .frame(width: Space.xl)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(badger.title).font(.headline)
                Text(badger.statusText).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .animation(reduceMotion ? nil : Motion.standard, value: badger.escalationTone)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(badger.title), \(badger.statusText)")
    }
}

#if DEBUG
extension ContentView {
    var debugHarness: some View {
        Section("Dev harness (device-verify)") {
            Button("New Badger — 10/25/45s notification ladder") {
                Task { await engine.create(title: "Test Badger", startAt: .now,
                                            rungs: Self.devNotificationLadder, maxSnoozeCount: 1) }
            }
            Button("New Badger — 10/25/45s breakthrough ladder") {
                Task { await engine.create(title: "AlarmKit Test Badger", startAt: .now,
                                            rungs: Self.devBreakthroughLadder, maxSnoozeCount: 1) }
            }
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
            if let ceilingResult {
                Text(ceilingResult).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            Button("Probe Live Activity ceiling (D1 / D3)") {
                Task {
                    ceilingResult = "probing LA…"
                    ceilingResult = await LAProbe.measureCeiling()
                }
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
    }

    var eventLogSection: some View {
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
}
#endif
