//
//  SoundLibraryTests.swift
//  BadgerKitTests — the curated catalog + the pure import validator (§10/D10, M7 CP1).
//

import Testing
import Foundation
@testable import BadgerKit

@Suite("BadgerKit SoundCatalog + import validator (§10/D10)")
struct SoundLibraryTests {

    // MARK: - Catalog

    @Test("catalog is the gentle→loud trio, ordered, with unique ids")
    func catalogShape() {
        let all = SoundCatalog.all
        #expect(all.map(\.id) == ["ahem", "badger", "red-alert"])
        #expect(Set(all.map(\.id)).count == all.count)
        #expect(all.allSatisfy { !$0.filename.isEmpty && !$0.subtitle.isEmpty })
    }

    @Test("sound(id:) resolves a known id and misses unknown")
    func lookup() {
        #expect(SoundCatalog.sound(id: "badger") == SoundCatalog.badger)
        #expect(SoundCatalog.sound(id: "nope") == nil)
    }

    @Test("a bundled sound's soundRef is builtIn(its id)")
    func soundRefMapping() {
        #expect(SoundCatalog.redAlert.soundRef == .builtIn(id: "red-alert"))
    }

    // MARK: - Import validator

    @Test("accepts each allowed encoding at or under 30s")
    func acceptsAllowed() {
        for enc in [SoundEncoding.linearPCM, .ima4, .uLaw, .aLaw] {
            #expect(SoundImportValidator.validate(durationSeconds: 12, encoding: enc) == nil)
        }
    }

    @Test("accepts exactly 30s, rejects just over")
    func durationBoundary() {
        #expect(SoundImportValidator.validate(durationSeconds: 30, encoding: .linearPCM) == nil)
        #expect(SoundImportValidator.validate(durationSeconds: 30.01, encoding: .linearPCM)
            == .tooLong(seconds: 30.01, max: 30))
    }

    @Test("rejects AAC/MP3/other by encoding, before length")
    func rejectsEncoding() {
        for enc in [SoundEncoding.aac, .mp3, .other] {
            #expect(SoundImportValidator.validate(durationSeconds: 5, encoding: enc)
                == .unsupportedEncoding(enc))
        }
        // Encoding is checked first: a too-long AAC reports the encoding, not the duration.
        #expect(SoundImportValidator.validate(durationSeconds: 99, encoding: .aac)
            == .unsupportedEncoding(.aac))
    }

    @Test("allowedEncodings is exactly the four playable formats")
    func allowedSet() {
        #expect(SoundImportValidator.allowedEncodings == [.linearPCM, .ima4, .uLaw, .aLaw])
        #expect(SoundImportValidator.maxDuration == 30)
    }

    // MARK: - SoundRef resolution (M7 CP4b)

    @Test("resolvedFilename: built-in via catalog, imported passthrough, unknown/renderedSpeech nil")
    func resolvedFilename() {
        #expect(SoundRef.builtIn(id: "badger").resolvedFilename == "Badger.caf")
        #expect(SoundRef.builtIn(id: "red-alert").resolvedFilename == "RedAlert.caf")
        #expect(SoundRef.builtIn(id: "nope").resolvedFilename == nil)      // unknown → system default
        #expect(SoundRef.imported(filename: "Mine.caf").resolvedFilename == "Mine.caf")
        #expect(SoundRef.renderedSpeech.resolvedFilename == nil)
    }
}
