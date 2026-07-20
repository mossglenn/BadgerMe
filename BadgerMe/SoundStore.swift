//
//  SoundStore.swift
//  BadgerMe — imported-sound management + preview (§10, M7 CP4b). The pure accept/reject decision
//  lives in BadgerKit's SoundImportValidator (CP1); this is the thin I/O glue: probe a picked file
//  with AVFoundation, validate, copy into Library/Sounds, scan/delete, and play a preview. Custom
//  sounds resolve from Library/Sounds (§20 gotcha), which is where both channels' named lookups look.
//

import Foundation
import AVFoundation
import BadgerKit

@MainActor
final class SoundStore {
    static let shared = SoundStore()
    private var player: AVAudioPlayer?

    private var soundsDir: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sounds", isDirectory: true)
    }

    /// Filenames of user-imported sounds in Library/Sounds.
    func mySounds() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: soundsDir.path))?
            .filter { !$0.hasPrefix(".") }.sorted() ?? []
    }

    /// Probe → validate (CP1) → copy into Library/Sounds. Throws `SoundImportRejection` if the file
    /// is too long or an unsupported encoding; returns the stored `SoundRef.imported` on success.
    func importSound(from src: URL) throws -> SoundRef {
        let scoped = src.startAccessingSecurityScopedResource()
        defer { if scoped { src.stopAccessingSecurityScopedResource() } }

        let (duration, encoding) = try probe(src)
        if let rejection = SoundImportValidator.validate(durationSeconds: duration, encoding: encoding) {
            throw rejection
        }
        try FileManager.default.createDirectory(at: soundsDir, withIntermediateDirectories: true)
        let dest = uniqueDestination(for: src.lastPathComponent)
        try FileManager.default.copyItem(at: src, to: dest)
        return .imported(filename: dest.lastPathComponent)
    }

    func deleteImported(_ filename: String) {
        try? FileManager.default.removeItem(at: soundsDir.appendingPathComponent(filename))
    }

    /// Resolve a SoundRef to a playable URL: imported → Library/Sounds, built-in → app bundle.
    func resolvedURL(for ref: SoundRef) -> URL? {
        guard let filename = ref.resolvedFilename else { return nil }
        let imported = soundsDir.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: imported.path) { return imported }
        return Bundle.main.url(forResource: filename, withExtension: nil)
    }

    /// Play a short preview (routed to .playback so it's audible even on silent).
    func preview(_ ref: SoundRef) {
        guard let url = resolvedURL(for: ref) else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }

    // MARK: - Private

    private func probe(_ url: URL) throws -> (duration: Double, encoding: SoundEncoding) {
        let file = try AVAudioFile(forReading: url)
        let format = file.fileFormat
        let rate = format.sampleRate
        let duration = rate > 0 ? Double(file.length) / rate : .greatestFiniteMagnitude
        return (duration, encoding(from: format.streamDescription.pointee.mFormatID))
    }

    private func encoding(from formatID: AudioFormatID) -> SoundEncoding {
        switch formatID {
        case kAudioFormatLinearPCM:  return .linearPCM
        case kAudioFormatAppleIMA4:  return .ima4
        case kAudioFormatULaw:       return .uLaw
        case kAudioFormatALaw:       return .aLaw
        case kAudioFormatMPEG4AAC:   return .aac
        case kAudioFormatMPEGLayer3: return .mp3
        default:                     return .other
        }
    }

    private func uniqueDestination(for filename: String) -> URL {
        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var candidate = soundsDir.appendingPathComponent(filename)
        var n = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(base)-\(n)" : "\(base)-\(n).\(ext)"
            candidate = soundsDir.appendingPathComponent(name)
            n += 1
        }
        return candidate
    }
}
