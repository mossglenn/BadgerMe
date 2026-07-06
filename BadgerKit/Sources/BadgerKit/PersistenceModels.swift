//
//  PersistenceModels.swift
//  BadgerKit — SwiftData @Model types (Phase 5 §6 / §7).
//
//  Queried enums are stored as raw String columns with computed accessors (P1's fix
//  for the SwiftData #Predicate crash). The persisted log row is `EventRecord`
//  because the reducer already owns the type name `Event` for the input-event enum.
//

import Foundation
import SwiftData

/// One commitment being escalated (§6).
@Model
final class Badger {
    @Attribute(.unique) var id: UUID
    var title: String
    var notes: String?
    var createdAt: Date
    var startAt: Date

    // Queried enums -> raw String columns + accessors (P1 lesson).
    var sourceRaw: String
    var stateRaw: String

    var currentLevel: Int
    var snoozeCount: Int
    /// Set while `state == .snoozed`; the wake time. resumeLevel == currentLevel.
    var snoozeUntil: Date?
    var resolvedAt: Date?

    var maxSnoozeCount: Int
    var tint: String
    var iconName: String?

    var armedAlarmIDs: [Int: UUID]
    var armedNotificationIDs: [Int: String]
    var liveActivityID: String?
    var focusTags: [String]

    @Relationship(deleteRule: .cascade) var ladder: BoundLadder?

    var source: TriggerSource {
        get { TriggerSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }
    var state: StoredBadgerState {
        get { StoredBadgerState(rawValue: stateRaw) ?? .pending }
        set { stateRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), title: String, notes: String? = nil,
         createdAt: Date = .now, startAt: Date,
         source: TriggerSource = .manual, state: StoredBadgerState = .pending,
         currentLevel: Int = 0, snoozeCount: Int = 0, snoozeUntil: Date? = nil,
         resolvedAt: Date? = nil, maxSnoozeCount: Int, tint: String = "accent",
         iconName: String? = nil, armedAlarmIDs: [Int: UUID] = [:],
         armedNotificationIDs: [Int: String] = [:], liveActivityID: String? = nil,
         focusTags: [String] = [], ladder: BoundLadder? = nil) {
        self.id = id
        self.title = title
        self.notes = notes
        self.createdAt = createdAt
        self.startAt = startAt
        self.sourceRaw = source.rawValue
        self.stateRaw = state.rawValue
        self.currentLevel = currentLevel
        self.snoozeCount = snoozeCount
        self.snoozeUntil = snoozeUntil
        self.resolvedAt = resolvedAt
        self.maxSnoozeCount = maxSnoozeCount
        self.tint = tint
        self.iconName = iconName
        self.armedAlarmIDs = armedAlarmIDs
        self.armedNotificationIDs = armedNotificationIDs
        self.liveActivityID = liveActivityID
        self.focusTags = focusTags
        self.ladder = ladder
    }
}

/// Reusable escalation definition (§6), edited independently of bound instances.
@Model
final class LadderTemplate {
    @Attribute(.unique) var id: UUID
    var name: String
    var rungs: [RungSpec]
    var defaultMaxSnoozeCount: Int
    var isBuiltIn: Bool

    init(id: UUID = UUID(), name: String, rungs: [RungSpec],
         defaultMaxSnoozeCount: Int, isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.rungs = rungs
        self.defaultMaxSnoozeCount = defaultMaxSnoozeCount
        self.isBuiltIn = isBuiltIn
    }
}

/// The ladder frozen onto a Badger at creation (§6): a value copy of the rungs.
@Model
final class BoundLadder {
    @Attribute(.unique) var id: UUID
    var sourceTemplateID: UUID?
    var rungs: [RungSpec]

    init(id: UUID = UUID(), sourceTemplateID: UUID? = nil, rungs: [RungSpec]) {
        self.id = id
        self.sourceTemplateID = sourceTemplateID
        self.rungs = rungs
    }
}

/// An append-only, immutable log row (§7). Linked to its Badger by `badgerID`
/// (queried by badgerID + sequence); persists a reducer `LoggedEvent`.
@Model
final class EventRecord {
    @Attribute(.unique) var id: UUID
    var badgerID: UUID
    var sequence: Int
    var timestamp: Date
    var kindRaw: String
    var level: Int?
    var sourceRaw: String
    var detail: [String: String]

    var kind: EventKind {
        get { EventKind(rawValue: kindRaw) ?? .reconciled }
        set { kindRaw = newValue.rawValue }
    }
    var source: EventSource {
        get { EventSource(rawValue: sourceRaw) ?? .system }
        set { sourceRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), badgerID: UUID, sequence: Int, timestamp: Date = .now,
         kind: EventKind, level: Int? = nil, source: EventSource,
         detail: [String: String] = [:]) {
        self.id = id
        self.badgerID = badgerID
        self.sequence = sequence
        self.timestamp = timestamp
        self.kindRaw = kind.rawValue
        self.level = level
        self.sourceRaw = source.rawValue
        self.detail = detail
    }
}
