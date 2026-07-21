//
//  SoundLibraryView.swift
//  BadgerMe — Settings ▸ Sounds management (§16/§10): browse and preview the curated catalog,
//  and import / preview / delete "My Sounds". Selection-free (unlike SoundPickerView, which binds a
//  rung's SoundRef); this is just library upkeep. Import uses the same SoundStore pipeline.
//

import SwiftUI
import UniformTypeIdentifiers
import BadgerKit

struct SoundLibraryView: View {
    @State private var mySounds: [String] = []
    @State private var showImporter = false
    @State private var importError: String?
    private let store = SoundStore.shared

    var body: some View {
        List {
            Section("Built-in") {
                ForEach(SoundCatalog.all) { sound in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sound.name)
                            Text(sound.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { store.preview(sound.soundRef) } label: { Image(systemName: "play.circle") }
                            .buttonStyle(.borderless).accessibilityLabel("Preview \(sound.name)")
                    }
                }
            }
            Section {
                if mySounds.isEmpty {
                    Text("No imported sounds yet.").foregroundStyle(.secondary)
                }
                ForEach(mySounds, id: \.self) { file in
                    HStack {
                        Text(file)
                        Spacer()
                        Button { store.preview(.imported(filename: file)) } label: { Image(systemName: "play.circle") }
                            .buttonStyle(.borderless).accessibilityLabel("Preview \(file)")
                    }
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
                Text("≤ 30 s, CAF/WAV/AIFF (PCM, IMA4, µ-law, or A-law). AAC/MP3 aren't supported. A Badger using a sound you delete falls back to the system default.")
            }
            if let importError {
                Section { Text(importError).font(.footnote).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Sounds")
        .onAppear(perform: refresh)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio],
                      allowsMultipleSelection: false, onCompletion: handleImport)
    }

    private func refresh() { mySounds = store.mySounds() }

    private func handleImport(_ result: Result<[URL], Error>) {
        importError = nil
        guard case .success(let urls) = result, let url = urls.first else { return }
        do {
            _ = try store.importSound(from: url)
            refresh()
        } catch let rejection as SoundImportRejection {
            switch rejection {
            case .tooLong(let s, let max):
                importError = "That sound is \(Int(s.rounded()))s — the limit is \(Int(max))s."
            case .unsupportedEncoding:
                importError = "That format isn't supported. Use CAF/WAV/AIFF (PCM, IMA4, µ-law, or A-law)."
            }
        } catch {
            importError = "Couldn't read that file as a sound."
        }
    }
}
