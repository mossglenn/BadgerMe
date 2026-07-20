//
//  SoundPickerView.swift
//  BadgerMe — choose a rung's sound (§10, M7 CP4b): system default, a curated built-in, or an
//  imported "My Sound"; with per-row preview, an importer (probe→validate→copy via SoundStore),
//  and swipe-to-delete for imports. Edits a SoundRef? binding owned by the rung editor.
//

import SwiftUI
import UniformTypeIdentifiers
import BadgerKit

struct SoundPickerView: View {
    @Binding var selection: SoundRef?
    @State private var mySounds: [String] = []
    @State private var showImporter = false
    @State private var importError: String?
    private let store = SoundStore.shared

    var body: some View {
        List {
            Section {
                soundRow(title: "Default (system)", subtitle: nil, ref: nil)
            }
            Section("Built-in") {
                ForEach(SoundCatalog.all) { s in
                    soundRow(title: s.name, subtitle: s.subtitle, ref: s.soundRef)
                }
            }
            Section {
                if mySounds.isEmpty {
                    Text("No imported sounds yet.").foregroundStyle(.secondary)
                }
                ForEach(mySounds, id: \.self) { file in
                    soundRow(title: file, subtitle: nil, ref: .imported(filename: file))
                }
                .onDelete { offsets in
                    for i in offsets { store.deleteImported(mySounds[i]) }
                    refresh()
                }
                Button { showImporter = true } label: {
                    Label("Import a sound…", systemImage: "square.and.arrow.down")
                }
            } header: {
                Text("My Sounds")
            } footer: {
                Text("≤ 30 s, CAF/WAV/AIFF (PCM, IMA4, µ-law, or A-law). AAC/MP3 aren't supported.")
            }
            if let importError {
                Section { Text(importError).font(.footnote).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Sound")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refresh)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio],
                      allowsMultipleSelection: false, onCompletion: handleImport)
    }

    private func soundRow(title: String, subtitle: String?, ref: SoundRef?) -> some View {
        HStack(spacing: 12) {
            Button {
                selection = ref
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                        if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    if selection == ref {
                        Image(systemName: "checkmark").foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let ref {
                Button { store.preview(ref) } label: { Image(systemName: "play.circle") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Preview \(title)")
            }
        }
    }

    private func refresh() { mySounds = store.mySounds() }

    private func handleImport(_ result: Result<[URL], Error>) {
        importError = nil
        guard case .success(let urls) = result, let url = urls.first else { return }
        do {
            selection = try store.importSound(from: url)
            refresh()
        } catch let rejection as SoundImportRejection {
            importError = message(for: rejection)
        } catch {
            importError = "Couldn't read that file as a sound."
        }
    }

    private func message(for rejection: SoundImportRejection) -> String {
        switch rejection {
        case .tooLong(let seconds, let max):
            return "That sound is \(Int(seconds.rounded()))s — the limit is \(Int(max))s."
        case .unsupportedEncoding:
            return "That format isn't supported. Use CAF/WAV/AIFF (PCM, IMA4, µ-law, or A-law)."
        }
    }
}
