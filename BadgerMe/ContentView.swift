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
    /// Set once by RootView after onboarding's "Create your first Badger" — auto-opens create.
    var startCreating: Bool = false
    /// DEBUG diagnostic (SP9/B1): probe the per-app AlarmKit alarm ceiling. nil in release.
    var probeCeiling: (@Sendable () async -> Int)? = nil

    @Query(sort: \Badger.createdAt, order: .reverse) private var badgers: [Badger]
    @State private var showCreate = false
    @State private var showSettings = false
    @Namespace private var heroNS
    @State private var didAutoCreate = false

    private var escalatingCount: Int { badgers.filter { !$0.isTerminal }.count }
    private var atCap: Bool { escalatingCount >= BadgerConfig.maxConcurrentEscalating }

    var body: some View {
        NavigationStack {
            List {
                if badgers.isEmpty {
                    VStack(spacing: Space.md) {
                        Image("badgerpaw")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text("Nothing's badgering you")
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                        Text("Add a Badger and it'll keep after you about something you'd otherwise let slide.")
                            .font(.badgerVoice(.callout))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button { Haptics.impact(.light); showCreate = true } label: {
                            Label("New Badger", systemImage: "plus")
                                .font(.headline)
                                .foregroundStyle(DesignTokens.onAccent)
                                .padding(.horizontal, Space.sm)
                                .padding(.vertical, Space.xxs)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DesignTokens.accent)
                        .padding(.top, Space.xs)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.xl)
                } else {
                    Section {
                        ForEach(badgers) { badger in
                            NavigationLink {
                                BadgerDetailView(badger: badger, engine: engine, heroNamespace: heroNS)
                            } label: {
                                BadgerRow(badger: badger)
                            }
                            .matchedTransitionSource(id: badger.id, in: heroNS)
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
            .sheet(isPresented: $showSettings) { SettingsView(engine: engine, permissions: permissions, probeCeiling: probeCeiling) }
        }
        .task { await engine.reconcileAll() }
        .onAppear { if startCreating && !didAutoCreate { didAutoCreate = true; showCreate = true } }
    }

    private var capFooter: some View {
        Label("Paws are full — resolve one to add another (\(BadgerConfig.maxConcurrentEscalating) max).",
              image: "badgerpaw.fill")
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
            badger.identityImage
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
