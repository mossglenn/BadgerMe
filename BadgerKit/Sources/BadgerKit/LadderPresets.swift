//
//  LadderPresets.swift
//  BadgerKit — the named built-in ladder presets (§10/D10, M7 CP1).
//
//  Seed content: the "long-and-soft / balanced / short-and-loud" trio (Gentle / Default / Urgent),
//  each encoding a prominence arc + the gentle→klaxon sound arc from SoundCatalog. Value-only here;
//  CP2 seeds these as `isBuiltIn` LadderTemplates by their stable `id` (idempotent upsert), and the
//  create flow's fallback moves from `BadgerLadders.defaultRungs` to the Default preset. Pure and
//  Foundation-only — unit-tested without a container.
//

import Foundation

/// A named, built-in ladder (§10/D10). Mirrors the seedable fields of `LadderTemplate` so CP2 can
/// build one directly. `id` is stable across launches so re-seeding dedupes rather than duplicates.
public struct LadderPreset: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let rungs: [RungSpec]
    public let defaultMaxSnoozeCount: Int

    public init(id: UUID, name: String, rungs: [RungSpec], defaultMaxSnoozeCount: Int) {
        self.id = id
        self.name = name
        self.rungs = rungs
        self.defaultMaxSnoozeCount = defaultMaxSnoozeCount
    }
}

public enum LadderPresets {
    // Stable ids (valid hex) so CP2 can re-seed idempotently by id.
    static let gentleID  = UUID(uuidString: "0000A0DE-0000-0000-0000-000000000001")!
    static let defaultID = UUID(uuidString: "0000A0DE-0000-0000-0000-000000000002")!
    static let urgentID  = UUID(uuidString: "0000A0DE-0000-0000-0000-000000000003")!

    /// A soft (notification) rung at a given prominence with a built-in sound.
    private static func soft(_ p: Prominence, _ s: BundledSound) -> ChannelAction {
        ChannelAction(channelID: "notification", prominence: p, soundRef: s.soundRef)
    }
    /// A hard (AlarmKit breakthrough) rung with a built-in sound.
    private static func hard(_ s: BundledSound) -> ChannelAction {
        ChannelAction(channelID: "alarmkit", prominence: .breakthrough, soundRef: s.soundRef)
    }

    /// Long-and-soft: never escalates past a time-sensitive notification; generous snooze budget.
    public static let gentle = LadderPreset(
        id: gentleID, name: "Gentle",
        rungs: [
            RungSpec(index: 0, delay: 0,    actions: [soft(.active, SoundCatalog.ahem)]),
            RungSpec(index: 1, delay: 900,  actions: [soft(.timeSensitive, SoundCatalog.badger)]),
            RungSpec(index: 2, delay: 2700, actions: [soft(.timeSensitive, SoundCatalog.badger)]),
        ],
        defaultMaxSnoozeCount: 3)

    /// Balanced: a soft opener, a time-sensitive middle, a breakthrough last rung.
    public static let balanced = LadderPreset(
        id: defaultID, name: "Default",
        rungs: [
            RungSpec(index: 0, delay: 0,   actions: [soft(.active, SoundCatalog.ahem)]),
            RungSpec(index: 1, delay: 300, actions: [soft(.timeSensitive, SoundCatalog.badger)]),
            RungSpec(index: 2, delay: 900, actions: [hard(SoundCatalog.redAlert)]),
        ],
        defaultMaxSnoozeCount: 2)

    /// Short-and-loud: quick intervals, breakthrough by the second rung, a tight snooze budget.
    public static let urgent = LadderPreset(
        id: urgentID, name: "Urgent",
        rungs: [
            RungSpec(index: 0, delay: 0,   actions: [soft(.timeSensitive, SoundCatalog.badger)]),
            RungSpec(index: 1, delay: 120, actions: [hard(SoundCatalog.redAlert)]),
            RungSpec(index: 2, delay: 300, actions: [hard(SoundCatalog.redAlert)]),
        ],
        defaultMaxSnoozeCount: 1)

    /// Gentle → Default → Urgent: the order Settings lists them and the picker offers them.
    public static let all: [LadderPreset] = [gentle, balanced, urgent]

    public static func preset(id: UUID) -> LadderPreset? { all.first { $0.id == id } }
}
