//
//  LadderListView.swift
//  BadgerMe — manage reusable ladder templates (§16, M7 CP4). Reads templates via @Query; create,
//  edit (user), duplicate (built-in), and delete (user) all route through the engine. Pushed from
//  Settings ▸ Ladders (CP5), so it's a plain view, not its own NavigationStack.
//

import SwiftUI
import SwiftData
import BadgerKit

struct LadderListView: View {
    let engine: BadgerEngine
    @Query(sort: \LadderTemplate.name) private var templates: [LadderTemplate]
    @State private var editorConfig: EditorConfig?

    var body: some View {
        List {
            Section {
                ForEach(templates) { t in
                    Button {
                        editorConfig = EditorConfig(templateID: t.id, name: t.name,
                                                    rungs: Self.editRungs(from: t),
                                                    maxSnooze: t.defaultMaxSnoozeCount,
                                                    isBuiltIn: t.isBuiltIn)
                    } label: {
                        LadderRow(template: t)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: deleteUserTemplates)
            } footer: {
                Text("Built-in ladders can't be edited — duplicate one to customise it.")
            }
        }
        .navigationTitle("Ladders")
        .sheet(item: $editorConfig) { cfg in
            LadderEditorView(engine: engine, templateID: cfg.templateID, name: cfg.name,
                             rungs: cfg.rungs, maxSnooze: cfg.maxSnooze, isBuiltIn: cfg.isBuiltIn)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editorConfig = EditorConfig(templateID: nil, name: "",
                                                rungs: [EditRung(delayMinutes: 0, prominence: .active,
                                                                 soundRef: SoundCatalog.ahem.soundRef)],
                                                maxSnooze: 1, isBuiltIn: false)
                } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New ladder")
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
            return EditRung(delayMinutes: spec.delay / 60,
                            prominence: action?.prominence ?? .timeSensitive,
                            soundRef: action?.soundRef)
        }
    }
}

private struct EditorConfig: Identifiable {
    let id = UUID()
    let templateID: UUID?
    let name: String
    let rungs: [EditRung]
    let maxSnooze: Int
    let isBuiltIn: Bool
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
