//
//  SoundLibrary.swift
//  BadgerKit — the curated built-in sound catalog + the pure import validator (§10/D10, M7 CP1).
//
//  Two pure concerns, no I/O: (1) the curated gentle → klaxon catalog the picker/preview/channels
//  resolve against, and (2) the accept/reject decision for a user-imported `.caf`, made from
//  already-probed facts (duration + encoding) so it's testable and enforced "on import, not at
//  fire time" (§10). The `.caf` assets the catalog names are added to the app bundle separately
//  (an asset task); rendered-speech (D11) is a fast-follow and not modelled here beyond SoundRef.
//

import Foundation

/// One curated, bundled alert sound (§10/D10). `id` is the stable catalog key AND the
/// `SoundRef.builtIn` id a rung stores; `filename` is the `.caf` resolved from the app bundle.
/// `subtitle` carries the dry gentle→klaxon editorial voice (§16).
public struct BundledSound: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let subtitle: String
    public let filename: String

    public init(id: String, name: String, subtitle: String, filename: String) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.filename = filename
    }

    /// The reference a `ChannelAction` stores to select this sound.
    public var soundRef: SoundRef { .builtIn(id: id) }
}

/// The curated built-in catalog — a gentle-to-klaxon arc (§10 D10, the Ahem → Badger → Red Alert
/// trio). Ordered gentle → loud (the order the picker shows them). `sound(id:)` backs
/// `SoundRef.builtIn` lookup; an unknown id falls back to the system default at the channel (§10).
public enum SoundCatalog {
    public static let ahem = BundledSound(
        id: "ahem", name: "Ahem",
        subtitle: "A polite throat-clear. Easy to ignore — which is rather the point, early on.",
        filename: "Ahem.caf")
    public static let badger = BundledSound(
        id: "badger", name: "Badger",
        subtitle: "The signature nudge: insistent, but still civil.",
        filename: "Badger.caf")
    public static let redAlert = BundledSound(
        id: "red-alert", name: "Red Alert",
        subtitle: "A klaxon. For when civility has plainly failed.",
        filename: "RedAlert.caf")

    /// Gentle → loud.
    public static let all: [BundledSound] = [ahem, badger, redAlert]

    /// Resolve a built-in id to its sound; nil if unknown (channel then uses the system default).
    public static func sound(id: String) -> BundledSound? { all.first { $0.id == id } }
}

/// Audio encodings for a custom sound (§10). The first four play reliably as alert sounds on
/// both the notification and AlarmKit channels; `aac`/`mp3` are refused; `other` covers anything
/// the probe couldn't classify (also refused).
public enum SoundEncoding: String, Equatable, Sendable, CaseIterable {
    case linearPCM, ima4, uLaw, aLaw
    case aac, mp3, other
}

/// Why an imported sound was rejected — surfaced verbatim by the import UI (§10 "validate on
/// import, not at fire time"). Carries the offending fact for a precise message.
public enum SoundImportRejection: Error, Equatable, Sendable {
    case unsupportedEncoding(SoundEncoding)
    case tooLong(seconds: Double, max: Double)
}

/// Pure accept/reject for an imported sound given its already-probed duration + encoding. The UI
/// does the AVFoundation probe; the DECISION lives here (≤30 s; Linear PCM / IMA4 / µ-law / A-law).
/// Encoding is checked before length so a wrong-format file reports the format, not its duration.
public enum SoundImportValidator {
    public static let maxDuration: TimeInterval = 30
    public static let allowedEncodings: Set<SoundEncoding> = [.linearPCM, .ima4, .uLaw, .aLaw]

    /// Returns the rejection reason, or `nil` when the sound is acceptable.
    public static func validate(durationSeconds: Double,
                                encoding: SoundEncoding) -> SoundImportRejection? {
        guard allowedEncodings.contains(encoding) else { return .unsupportedEncoding(encoding) }
        guard durationSeconds <= maxDuration else {
            return .tooLong(seconds: durationSeconds, max: maxDuration)
        }
        return nil
    }
}
