//
//  CreateBadgerIntent.swift
//  BadgerKit — the manual/inbound create entry point (M4, §11, headless-first L3).
//
//  Chainable and usable in time/location Automations ("when I leave work, badger me…").
//  The `ladder` parameter resolves a persisted template's rungs; with none named it uses
//  `engine.defaultLadder()` (the configured default, else the built-in Default preset — M7 CP2).
//  Runs in-app (plain AppIntent, no AppIntents extension per D7) where the engine @Dependency is
//  registered, without foregrounding (openAppWhenRun stays false).
//

import Foundation

#if os(iOS)
import AppIntents

public struct CreateBadgerIntent: AppIntent {
    public static let title: LocalizedStringResource = "Create Badger"
    public static let description = IntentDescription(
        "Start badgering yourself about a commitment until you mark it done.")

    @Parameter(title: "Title") public var title: String
    @Parameter(title: "Notes") public var notes: String?
    @Parameter(title: "Start") public var startDate: Date?
    @Parameter(title: "Ladder") public var ladder: LadderEntity?

    @Dependency public var engine: BadgerEngine

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<BadgerEntity> {
        let start = startDate ?? Date()
        let resolved: (rungs: [RungSpec], maxSnoozeCount: Int)?
        if let ladder { resolved = await engine.ladderRungs(templateID: ladder.id) } else { resolved = nil }
        let chosen: (rungs: [RungSpec], maxSnoozeCount: Int)
        if let resolved { chosen = resolved } else { chosen = await engine.defaultLadder() }
        let rungs = chosen.rungs
        let maxSnooze = chosen.maxSnoozeCount

        let id = await engine.create(title: title, notes: notes, startAt: start,
                                     rungs: rungs, maxSnoozeCount: maxSnooze)
        let entity = await engine.snapshot(id: id).map(BadgerEntity.init)
            ?? BadgerEntity(id: id, title: title)
        return .result(value: entity)
    }
}
#endif
