//
//  FocusTagsView.swift
//  BadgerMe — edit a Badger's Focus-scope tags (§13, M7 CP4c). Writes through
//  engine.setFocusTags, which sanitises and re-evaluates arming under the active Focus filter — so
//  editing tags here is what unblocks the on-device Focus-scope check. Suggestions come from tags
//  already in use across Badgers (engine.allFocusTags).
//

import SwiftUI
import BadgerKit

struct FocusTagsView: View {
    let badger: Badger
    let engine: BadgerEngine

    @State private var tags: [String]
    @State private var newTag = ""
    @State private var suggestions: [String] = []

    init(badger: Badger, engine: BadgerEngine) {
        self.badger = badger
        self.engine = engine
        _tags = State(initialValue: badger.focusTags)
    }

    private var normalizedNew: String { newTag.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        List {
            Section {
                if tags.isEmpty {
                    Text("No tags yet.").foregroundStyle(.secondary)
                }
                ForEach(tags, id: \.self) { Text($0) }
                    .onDelete(perform: remove)
            } header: {
                Text("Tags")
            } footer: {
                Text("A Focus filter can limit escalation to Badgers with a chosen tag (Settings ▸ Focus ▸ this app).")
            }

            Section("Add a tag") {
                HStack {
                    TextField("e.g. work, home", text: $newTag)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(addTyped)
                    Button("Add", action: addTyped).disabled(normalizedNew.isEmpty)
                }
            }

            if !suggestions.isEmpty {
                Section("In use on other Badgers") {
                    ForEach(suggestions, id: \.self) { tag in
                        Button { add(tag) } label: { Label(tag, systemImage: "plus.circle") }
                    }
                }
            }
        }
        .navigationTitle("Focus Tags")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refreshSuggestions)
    }

    private func addTyped() {
        add(normalizedNew)
        newTag = ""
    }

    private func add(_ raw: String) {
        let tag = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty, !tags.contains(tag) else { return }
        tags.append(tag)
        commit()
    }

    private func remove(_ offsets: IndexSet) {
        tags.remove(atOffsets: offsets)
        commit()
    }

    private func commit() {
        let updated = tags
        Task {
            await engine.setFocusTags(updated, on: badger.id)
            tags = badger.focusTags        // reflect the engine's sanitised result (trim/dedupe/sort)
            refreshSuggestions()
        }
    }

    private func refreshSuggestions() {
        suggestions = engine.allFocusTags().filter { !tags.contains($0) }
    }
}
