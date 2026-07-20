//
//  CreateBadgerView.swift
//  BadgerMe — the create sheet (§16, M7 CP3). A thin client of the engine (L3): it gathers a
//  title/notes/start + a ladder preset and calls engine.create. Presets come from BadgerKit's
//  LadderPresets (CP1); CP4 will also offer user-created templates here.
//

import SwiftUI
import BadgerKit

struct CreateBadgerView: View {
    let engine: BadgerEngine
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var notes = ""
    @State private var startNow = true
    @State private var startDate = Date()
    @State private var presetID = LadderPresets.balanced.id

    private var selectedPreset: LadderPreset {
        LadderPresets.all.first { $0.id == presetID } ?? LadderPresets.balanced
    }
    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Commitment") {
                    TextField("What are you badgering yourself about?", text: $title, axis: .vertical)
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                }
                Section("Escalation ladder") {
                    Picker("Ladder", selection: $presetID) {
                        ForEach(LadderPresets.all) { Text($0.name).tag($0.id) }
                    }
                    LadderPreview(preset: selectedPreset)
                }
                Section("Start") {
                    Toggle("Start now", isOn: $startNow)
                    if !startNow {
                        DatePicker("Start at", selection: $startDate)
                            .datePickerStyle(.compact)
                    }
                }
            }
            .navigationTitle("New Badger")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: create).disabled(trimmedTitle.isEmpty)
                }
            }
        }
    }

    private func create() {
        let t = trimmedTitle
        let n = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let preset = selectedPreset
        let start = startNow ? Date() : startDate
        Task {
            await engine.create(title: t, notes: n.isEmpty ? nil : n, startAt: start,
                                rungs: preset.rungs, maxSnoozeCount: preset.defaultMaxSnoozeCount)
            dismiss()
        }
    }
}
