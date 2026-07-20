//
//  CreateBadgerView.swift
//  BadgerMe — the create sheet (§16, M7 CP3/CP4). A thin client of the engine (L3): it gathers a
//  title/notes/start + a ladder and calls engine.create. The ladder picker reads all stored
//  templates (built-in presets + user-created, M7 CP4) via @Query; the default selection is the
//  configured default ladder (BadgerConfig.defaultLadderID).
//

import SwiftUI
import SwiftData
import BadgerKit

struct CreateBadgerView: View {
    let engine: BadgerEngine
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \LadderTemplate.name) private var templates: [LadderTemplate]

    @State private var title = ""
    @State private var notes = ""
    @State private var startNow = true
    @State private var startDate = Date()
    @State private var ladderID = BadgerConfig.defaultLadderID

    private var selected: LadderTemplate? { templates.first { $0.id == ladderID } ?? templates.first }
    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Commitment") {
                    TextField("What are you badgering yourself about?", text: $title, axis: .vertical)
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                }
                Section("Escalation ladder") {
                    Picker("Ladder", selection: $ladderID) {
                        ForEach(templates) { Text($0.name).tag($0.id) }
                    }
                    if let s = selected {
                        LadderPreview(rungs: s.rungs, maxSnooze: s.defaultMaxSnoozeCount)
                    }
                }
                Section("Start") {
                    Toggle("Start now", isOn: $startNow)
                    if !startNow {
                        DatePicker("Start at", selection: $startDate).datePickerStyle(.compact)
                    }
                }
            }
            .navigationTitle("New Badger")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: create).disabled(trimmedTitle.isEmpty || selected == nil)
                }
            }
            .onAppear {
                if !templates.contains(where: { $0.id == ladderID }) {
                    ladderID = templates.first?.id ?? ladderID
                }
            }
        }
    }

    private func create() {
        let t = trimmedTitle
        let n = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let chosenID = selected?.id ?? ladderID
        let start = startNow ? Date() : startDate
        Task {
            let ladder = engine.ladderRungs(templateID: chosenID) ?? engine.defaultLadder()
            await engine.create(title: t, notes: n.isEmpty ? nil : n, startAt: start,
                                rungs: ladder.rungs, maxSnoozeCount: ladder.maxSnoozeCount)
            dismiss()
        }
    }
}
