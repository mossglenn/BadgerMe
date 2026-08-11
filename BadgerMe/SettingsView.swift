//
//  SettingsView.swift
//  BadgerMe — Settings root (§16/§17): escalation defaults, snooze options, the Ladders + Sounds
//  libraries, permission status with a deep link, and a Focus-filter explainer. A client of the
//  engine + BadgerConfig; holds no escalation logic (L3).
//

import SwiftUI
import SwiftData
import UIKit
import AlarmKit
import BadgerKit

struct SettingsView: View {
    let engine: BadgerEngine
    let permissions: Permissions
    var probeCeiling: (@Sendable () async -> Int)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Query(sort: \LadderTemplate.name) private var templates: [LadderTemplate]

    @State private var defaultLadderID = BadgerConfig.defaultLadderID
    @State private var defaultSnooze = BadgerConfig.defaultSnoozeMinutes
    @State private var snoozeOptions = BadgerConfig.snoozeOptionsMinutes
    @State private var newOption = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Defaults") {
                    Picker("Default ladder", selection: $defaultLadderID) {
                        ForEach(templates) { Text($0.name).tag($0.id) }
                    }
                    .onChange(of: defaultLadderID) { BadgerConfig.defaultLadderID = defaultLadderID }

                    Picker("Default snooze", selection: $defaultSnooze) {
                        ForEach(snoozeOptions, id: \.self) { Text("\($0) min").tag($0) }
                    }
                    .onChange(of: defaultSnooze) { BadgerConfig.setDefaultSnoozeMinutes(defaultSnooze) }
                }

                Section {
                    ForEach(snoozeOptions, id: \.self) { Text("\($0) min") }
                        .onDelete(perform: removeOption)
                    HStack {
                        TextField("Add minutes", text: $newOption).keyboardType(.numberPad)
                        Button("Add", action: addOption).disabled((Int(newOption) ?? 0) <= 0)
                    }
                } header: {
                    Text("Snooze options")
                } footer: {
                    Text("Durations offered when you tap Snooze on a Badger. \u{201C}Default snooze\u{201D} above is the one-tap duration used by the list swipe, the notification action, and Siri.")
                }

                Section("Library") {
                    NavigationLink { LadderListView(engine: engine) } label: {
                        Label("Ladders", systemImage: "square.stack.3d.up")
                    }
                    NavigationLink { SoundLibraryView() } label: {
                        Label("Sounds", systemImage: "speaker.wave.2.fill")
                    }
                }

                Section {
                    permissionRow("Notifications", permissions.notifications.label,
                                  ok: permissions.notifications.isAllowed)
                    permissionRow("Alarms", permissions.alarms.label,
                                  ok: permissions.alarms == .authorized)
                    Button("Open iOS Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                } header: {
                    Text("Permissions")
                } footer: {
                    Text("Alarms let BadgerMe pierce silent and Focus. Without them, escalation is limited to notifications.")
                }

                Section {
                    Label("A Focus filter can limit which Badgers escalate (by tag) and cap how loud they get during a Focus. Set it up in iOS Settings ▸ Focus ▸ your Focus ▸ Filters ▸ BadgerMe.",
                          systemImage: "moon.fill")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: {
                    Text("Focus")
                }

                Section {
                    NavigationLink { HelpView() } label: {
                        Label("How BadgerMe works", systemImage: "questionmark.circle")
                    }
                } header: {
                    Text("Help")
                }

                #if DEBUG
                Section {
                    NavigationLink { DeveloperView(engine: engine, probeCeiling: probeCeiling) } label: {
                        Label("Developer", systemImage: "hammer")
                    }
                } header: {
                    Text("Developer")
                }
                #endif
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await permissions.refresh() }
            .onAppear(perform: syncFromConfig)
        }
    }

    private func syncFromConfig() {
        snoozeOptions = BadgerConfig.snoozeOptionsMinutes
        defaultLadderID = BadgerConfig.defaultLadderID
        defaultSnooze = BadgerConfig.defaultSnoozeMinutes
        if !snoozeOptions.contains(defaultSnooze), let first = snoozeOptions.first {
            defaultSnooze = first
            BadgerConfig.setDefaultSnoozeMinutes(first)
        }
    }

    private func permissionRow(_ title: String, _ status: String, ok: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            Label(status, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.circle")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(ok ? DesignTokens.positive : DesignTokens.escWarn)
        }
        .accessibilityElement(children: .combine)
    }

    private func addOption() {
        guard let m = Int(newOption), m > 0 else { return }
        snoozeOptions = BadgerConfig.sanitizedSnoozeOptions(snoozeOptions + [m])
        BadgerConfig.snoozeOptionsMinutes = snoozeOptions
        newOption = ""
    }

    private func removeOption(_ offsets: IndexSet) {
        var opts = snoozeOptions
        opts.remove(atOffsets: offsets)
        snoozeOptions = BadgerConfig.sanitizedSnoozeOptions(opts)
        BadgerConfig.snoozeOptionsMinutes = snoozeOptions
        if !snoozeOptions.contains(defaultSnooze), let first = snoozeOptions.first {
            defaultSnooze = first
            BadgerConfig.setDefaultSnoozeMinutes(first)
        }
    }
}
