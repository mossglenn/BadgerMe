//
//  BadgerActivityAttributes.swift
//  BadgerKit — the ambient Live Activity's shared type (§12, L7).
//
//  The per-Badger "never-stall" summary activity, distinct from AlarmKit's own per-rung
//  countdown presentation (that one is keyed on AlarmAttributes<BadgerAlarmMetadata>, CP1).
//  Lives in the package so the app (starts/updates activities) and the widget (renders them)
//  share one type — spec §4. Guarded #if os(iOS) so the macOS `swift test`
//  core never compiles it; excluded there, exercised by the iOS app/widget build.
//
//  Privacy split (§12/L8): the static attributes are PRIVATE and never leave the device;
//  ContentState is non-sensitive and is the only part a future relay could update.
//

#if os(iOS)
import Foundation
import ActivityKit

public struct BadgerActivityAttributes: ActivityAttributes {
    // Static; set at start; PRIVATE — never sent off device.
    public let badgerID: UUID
    public let title: String
    public let ladderSummary: String?
    public let tint: String?        // color token, resolved in the widget
    public let iconName: String?    // SF Symbol

    public init(badgerID: UUID, title: String, ladderSummary: String? = nil,
                tint: String? = nil, iconName: String? = nil) {
        self.badgerID = badgerID
        self.title = title
        self.ladderSummary = ladderSummary
        self.tint = tint
        self.iconName = iconName
    }

    // Volatile; NON-sensitive; the only part a future relay could update (§12/L8).
    public struct ContentState: Codable, Hashable, Sendable {
        public var currentLevelIndex: Int
        public var totalLevels: Int
        public var nextFireDate: Date?   // fixed target for system-driven timer text (§12)
        public var phase: Phase
        public var staleDate: Date?      // set == nextFireDate so the system flips to overdue

        public init(currentLevelIndex: Int, totalLevels: Int, nextFireDate: Date?,
                    phase: Phase, staleDate: Date?) {
            self.currentLevelIndex = currentLevelIndex
            self.totalLevels = totalLevels
            self.nextFireDate = nextFireDate
            self.phase = phase
            self.staleDate = staleDate
        }
    }

    /// Presentation phase (§12). Mirrors the reducer's logical `ActivityPhase` (internal to
    /// the locked core); the controller maps onto this when building ContentState. `overdue`
    /// is presentation-only — applied by the widget when `staleDate` passes, never emitted.
    public enum Phase: String, Codable, Hashable, Sendable {
        case armed, escalating, repeating, snoozed, done, stopped, overdue
    }
}
#endif
