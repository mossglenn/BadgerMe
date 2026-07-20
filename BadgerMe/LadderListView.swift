//
//  LadderListView.swift
//  BadgerMe — manage reusable ladder templates (§16, M7 CP4). Reads templates via @Query; create,
//  edit (user), duplicate (built-in), and delete (user) all route through the engine.
//

import SwiftUI
import SwiftData
import BadgerKit

struct LadderListView: View {
    let engine: BadgerEngine
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \LadderTemplate.name) private var templates: [LadderTemplate]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(templates) { t in
                        NavigationLink {
                            LadderEditorView(engine: engine, templateID: t.id, name: t.name,
                                             rungs: Self.editRungs(from: t),
                                             maxSnooze: t.defaultMaxSnoozeCount, isBuiltIn: t.isBuiltIn)
                        } label: {
                            LadderRow(template: t)
                        }
                    }
                    .onDelete(perform: deleteUserTemplates)
                } footer: {
                    Text("Built-in ladders can't be edited — duplicate one to customise it.")
                }
            }
            .navigationTitle("Ladders")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        LadderEditorView(engine: engine, templateID: nil, name: "",
                                         rungs: [EditRung(delayMinutes: 0, prominence: .active,
                                                          soundID: SoundCatalog.ahem.id)],
                                         maxSnooze: 1, isBuiltIn: false)
                    } label: { Image(systemName: "plus") }
                        .accessibilityLabel("New ladder")
                }
            }
        }
    }

    private func deleteUserTemplates(_ offsets: IndexSet) {
        for i in offsets where !templates[i].isBuiltIn {
            engine.deleteTemplate(id: templates[i].id)
        }
    }

    /// Convert a stored template's rungs into the editor's local model.
    static func editRungs(from t: LadderTemplate) -> [EditRung] {
        t.rungs.sorted { $0.index < $1.index }.map { spec in
            let action = spec.actions.first
            let soundID: String? = {
                if case let .builtIn(id) = action?.soundRef { return id }
                return nil
            }()
            return EditRung(delayMinutes: spec.delay / 60,
                            prominence: action?.prominence ?? .timeSensitive, soundID: soundID)
        }
    }
}

private struct LadderRow: View {
    let template: LadderTemplate

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(template.name).font(.headline)
                Text("\(template.rungs.count) rung\(template.rungs.count == 1 ? "" : "s") · snooze budget \(template.defaultMaxSnoozeCount)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if template.isBuiltIn {
                Image(systemName: "lock.fill").foregroundStyle(.secondary).imageScale(.small)
                    .accessibilityLabel("Built-in")
            }
        }
        .accessibilityElement(children: .combine)
    }
}
