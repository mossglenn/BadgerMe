//
//  LadderEditorView.swift
//  BadgerMe — build/edit a reusable ladder template (§16, M7 CP4). Edits a local value copy and
//  persists via engine.saveTemplate (which preserves order + re-indexes; delays are incremental
//  gaps, D8). Built-in templates are read-only here (the seed owns them); they can be duplicated
//  into an editable user template. Per-rung sound is chosen via SoundPickerView (CP4b).
//

import SwiftUI
import BadgerKit

struct EditRung: Identifiable {
    let id = UUID()
    var delayMinutes: Double
    var prominence: BadgerKit.Prominence
    var soundRef: SoundRef?        // built-in, imported, or nil = system default
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
            ForEach($rungs) { $rung in
                Section {
                    HStack {
                        Text("Wait").foregroundStyle(.secondary)
                        Stepper("\(Int(rung.delayMinutes)) min",
                                value: $rung.delayMinutes, in: 0...1440, step: 1)
                    }
                    Picker("Prominence", selection: $rung.prominence) {
                        Text("Notify").tag(BadgerKit.Prominence.active)
                        Text("Time-sensitive").tag(BadgerKit.Prominence.timeSensitive)
                        Text("Alarm (breakthrough)").tag(BadgerKit.Prominence.breakthrough)
                    }
                    NavigationLink {
                        SoundPickerView(selection: $rung.soundRef)
                    } label: {
                        HStack {
                            Text("Sound")
                            Spacer()
                            Text(ConsoleFormat.soundName(rung.soundRef)).foregroundStyle(.secondary)
                        }
                    }
                    if !isBuiltIn {
                        Button(role: .destructive) {
                            rungs.removeAll { $0.id == rung.id }
                        } label: { Text("Remove rung") }
                    }
                } header: {
                    Text("Rung \(number(of: rung))")
                }
                .disabled(isBuiltIn)
            }
            if !isBuiltIn {
                Section {
                    Button { addRung() } label: { Label("Add rung", systemImage: "plus") }
                } footer: {
                    Text("Each rung's delay is the wait after the previous rung fires (the first is measured from the Badger's start).")
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
        // D8 (M7): each rung's delay is the gap after the previous rung — a new rung defaults to
        // 5 min after the one before (the first rung fires at start).
        rungs.append(EditRung(delayMinutes: rungs.isEmpty ? 0 : 5,
                              prominence: .timeSensitive, soundRef: SoundCatalog.badger.soundRef))
    }

    private func number(of rung: EditRung) -> Int {
        (rungs.firstIndex { $0.id == rung.id } ?? 0) + 1
    }

    private func specs() -> [RungSpec] {
        rungs.map { r in
            let channel = r.prominence == .breakthrough ? "alarmkit" : "notification"
            return RungSpec(index: 0, delay: r.delayMinutes * 60,
                            actions: [ChannelAction(channelID: channel, prominence: r.prominence,
                                                    soundRef: r.soundRef)])
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
