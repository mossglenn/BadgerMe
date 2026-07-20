//
//  LadderEditorView.swift
//  BadgerMe — build/edit a reusable ladder template (§16, M7 CP4). Edits a local value copy and
//  persists via engine.saveTemplate (which delay-sorts + re-indexes). Built-in templates are
//  read-only here (the seed owns them); they can be duplicated into an editable user template.
//  The per-rung sound is curated-only for now; CP4c adds the full picker (curated + My Sounds).
//

import SwiftUI
import BadgerKit

struct EditRung: Identifiable {
    let id = UUID()
    var delayMinutes: Double
    var prominence: BadgerKit.Prominence
    var soundID: String?          // curated SoundCatalog id; nil = system default
}

struct LadderEditorView: View {
    let engine: BadgerEngine
    let templateID: UUID?         // nil = new template
    let isBuiltIn: Bool
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var rungs: [EditRung]
    @State private var maxSnooze: Int

    init(engine: BadgerEngine, templateID: UUID?, name: String,
         rungs: [EditRung], maxSnooze: Int, isBuiltIn: Bool) {
        self.engine = engine
        self.templateID = templateID
        self.isBuiltIn = isBuiltIn
        _name = State(initialValue: name)
        _rungs = State(initialValue: rungs)
        _maxSnooze = State(initialValue: maxSnooze)
    }

    private var canSave: Bool {
        !isBuiltIn && !name.trimmingCharacters(in: .whitespaces).isEmpty && !rungs.isEmpty
    }

    var body: some View {
        Form {
            if isBuiltIn {
                Section {
                    Label("Built-in ladder — read-only. Duplicate it to make your own.",
                          systemImage: "lock.fill").font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("Name") {
                TextField("Ladder name", text: $name).disabled(isBuiltIn)
            }
            Section("Rungs (soonest first)") {
                ForEach($rungs) { $rung in RungEditor(rung: $rung, disabled: isBuiltIn) }
                    .onDelete { if !isBuiltIn { rungs.remove(atOffsets: $0) } }
                if !isBuiltIn {
                    Button { addRung() } label: { Label("Add rung", systemImage: "plus") }
                }
            }
            Section("Snooze budget") {
                Stepper("Snoozes before escalating: \(maxSnooze)", value: $maxSnooze, in: 0...10)
                    .disabled(isBuiltIn)
            }
        }
        .navigationTitle(templateID == nil ? "New Ladder" : name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isBuiltIn {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Duplicate") { duplicate() }
                }
            } else {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!canSave)
                }
            }
        }
    }

    private func addRung() {
        let nextDelay = (rungs.map(\.delayMinutes).max() ?? 0) + 5
        rungs.append(EditRung(delayMinutes: rungs.isEmpty ? 0 : nextDelay,
                              prominence: .timeSensitive, soundID: SoundCatalog.badger.id))
    }

    private func specs() -> [RungSpec] {
        rungs.map { r in
            let channel = r.prominence == .breakthrough ? "alarmkit" : "notification"
            let sound: SoundRef? = r.soundID.map { .builtIn(id: $0) }
            return RungSpec(index: 0, delay: r.delayMinutes * 60,
                            actions: [ChannelAction(channelID: channel, prominence: r.prominence,
                                                    soundRef: sound)])
        }
    }

    private func save() {
        engine.saveTemplate(id: templateID ?? UUID(),
                            name: name.trimmingCharacters(in: .whitespaces),
                            rungs: specs(), maxSnoozeCount: maxSnooze)
        dismiss()
    }

    private func duplicate() {
        engine.saveTemplate(name: name + " copy", rungs: specs(), maxSnoozeCount: maxSnooze)
        dismiss()
    }
}

private struct RungEditor: View {
    @Binding var rung: EditRung
    let disabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("After").foregroundStyle(.secondary)
                Stepper("\(Int(rung.delayMinutes)) min", value: $rung.delayMinutes, in: 0...1440, step: 1)
            }
            Picker("Prominence", selection: $rung.prominence) {
                Text("Notify").tag(BadgerKit.Prominence.active)
                Text("Time-sensitive").tag(BadgerKit.Prominence.timeSensitive)
                Text("Alarm (breakthrough)").tag(BadgerKit.Prominence.breakthrough)
            }
            Picker("Sound", selection: $rung.soundID) {
                Text("Default").tag(String?.none)
                ForEach(SoundCatalog.all) { Text($0.name).tag(String?.some($0.id)) }
            }
        }
        .disabled(disabled)
        .accessibilityElement(children: .contain)
    }
}
