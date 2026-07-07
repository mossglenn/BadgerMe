//
//  PersistenceModels.swift
//  BadgerKit — SwiftData @Model types (Phase 5 §6 / §7).
//
//  Queried enums are stored as raw String columns with computed accessors (P1's fix
//  for the SwiftData #Predicate crash). The persisted log row is `EventRecord`
//  because the reducer already owns the type name `Event` for the input-event enum.
//
//  Public from M2: the app target queries these directly (@Query in the console /
//  dev harness) and the engine composition root lives in the app. The typed
//  EventRecord.kind/source accessors stay internal (they expose the reducer's
//  module-internal EventKind/EventSource); the raw String columns are public. When
//  the M7 history UI needs typed kinds, promote those two enums to public then.
//

import Foundation
import SwiftData

/// One commitment being escalated (§6).
@Model
public final class Badger {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var notes: String?
    public var createdAt: Date
    public var startAt: Date

    // Queried enums -> raw String columns + accessors (P1 lesson).
    public var sourceRaw: String
    public var stateRaw: String

    public var currentLevel: Int
    public var snoozeCount: Int
    /// Set while `state == .snoozed`; the wake time. resumeLevel == currentLevel.
    public var snoozeUntil: Date?
    public var resolvedAt: Date?

    public var maxSnoozeCount: Int
    public var tint: String
    public var iconName: String?

    public var armedAlarmIDs: [Int: UUID]
    public var armedNotificationIDs: [Int: String]
    public var liveActivityID: String?
    public var focusTags: [String]

    @Relationship(deleteRule: .cascade) public var ladder: BoundLadder?

    public var source: TriggerSource {
        get { TriggerSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }
    public var state: StoredBadgerState {
        get { StoredBadgerState(rawValue: stateRaw) ?? .pending }
        set { stateRaw = newValue.rawValue }
    }

    public init(id: UUID = UUID(), title: String, notes: String? = nil,
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
public final class LadderTemplate {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var rungs: [RungSpec]
    public var defaultMaxSnoozeCount: Int
    public var isBuiltIn: Bool

    public init(id: UUID = UUID(), name: String, rungs: [RungSpec],
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
public final class BoundLadder {
    @Attribute(.unique) public var id: UUID
    public var sourceTemplateID: UUID?
    public var rungs: [RungSpec]

    public init(id: UUID = UUID(), sourceTemplateID: UUID? = nil, rungs: [RungSpec]) {
        self.id = id
        self.sourceTemplateID = sourceTemplateID
        self.rungs = rungs
    }
}

/// An append-only, immutable log row (§7). Linked to its Badger by `badgerID`
/// (queried by badgerID + sequence); persists a reducer `LoggedEvent`.
@Model
public final class EventRecord {
    @Attribute(.unique) public var id: UUID
    public var badgerID: UUID
    public var sequence: Int
    public var timestamp: Date
    public var kindRaw: String
    public var level: Int?
    public var sourceRaw: String
    public var detail: [String: String]

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
