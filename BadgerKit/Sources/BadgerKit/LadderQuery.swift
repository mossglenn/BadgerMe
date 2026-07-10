//
//  LadderQuery.swift
//  BadgerKit — LadderEntity's default query (M4, §11).
//
//  Small template set: resolve by id and enumerate all. Returns [] until M7 seeds the
//  named presets (Gentle/Default/Urgent, D10).
//

import Foundation

#if os(iOS)
import AppIntents

public struct LadderQuery: EntityQuery {
    @Dependency public var engine: BadgerEngine

    public init() {}

    public func entities(for identifiers: [UUID]) async throws -> [LadderEntity] {
        let ids = Set(identifiers)
        return await engine.ladderTemplateSnapshots()
            .filter { ids.contains($0.id) }
            .map(LadderEntity.init)
    }

    public func suggestedEntities() async throws -> [LadderEntity] {
        await engine.ladderTemplateSnapshots().map(LadderEntity.init)
    }
}
#endif
