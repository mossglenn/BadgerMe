//
//  DomainModel.swift
//  BadgerKit — value types for the declarative ladder + persistence (Phase 5 §6).
//
//  Codable value types (not @Model entities): a BoundLadder freezes a RungSpec
//  array by simple value copy, and rungs/actions are never queried independently.
//
//  Public surface: these are consumed by the app target (dev harness + future
//  console) to build ladders and read Badger data, so the ladder value types are
//  public from M2 on. The reducer's own domain types stay module-internal.
//

import Foundation

/// How a Badger came to exist (§6). v1 populates only `.manual`.
public enum TriggerSource: String, Codable, CaseIterable, Sendable {
    case manual, inboundAutomation, appleReminders, calendar
}

/// How hard an alert pierces silence/Focus (§10). Lives inside a ChannelAction,
/// which is never queried, so a direct enum is fine (no raw-column needed).
public enum Prominence: String, Codable, CaseIterable, Sendable {
    case passive, active, timeSensitive, breakthrough
}

/// Reference into the sound library (§10). `.renderedSpeech` is registered now,
/// implemented as a fast-follow (D11).
public enum SoundRef: Codable, Equatable, Sendable {
    case builtIn(id: String)
    case imported(filename: String)
    case renderedSpeech
}

/// "Do this via this channel at this prominence" (§6).
public struct ChannelAction: Codable, Equatable, Sendable {
    public var channelID: String
    public var prominence: Prominence
    public var soundRef: SoundRef?
    public var message: String?
    /// Reserved for future channels (shortcutName / webhookURL); unused by v1.
    public var payload: [String: String]?

    public init(channelID: String, prominence: Prominence, soundRef: SoundRef? = nil,
                message: String? = nil, payload: [String: String]? = nil) {
        self.channelID = channelID
        self.prominence = prominence
        self.soundRef = soundRef
        self.message = message
        self.payload = payload
    }
}

/// One ladder step (§6): a delay relative to start (D8) + one or more actions.
public struct RungSpec: Codable, Equatable, Sendable {
    public var index: Int
    public var delay: TimeInterval
    public var actions: [ChannelAction]

    public init(index: Int, delay: TimeInterval, actions: [ChannelAction]) {
        self.index = index
        self.delay = delay
        self.actions = actions
    }
}

/// The persisted lifecycle discriminator (§6/§8). Raw-String column on `Badger`;
/// the reducer's `BadgerState` (with associated values) is reconstructed from this
/// plus `currentLevel` / `snoozeUntil` in the engine mapping.
public enum StoredBadgerState: String, Codable, CaseIterable, Sendable {
    case pending, active, snoozed, done, stopped
}
