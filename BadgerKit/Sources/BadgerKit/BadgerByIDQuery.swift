//
//  BadgerByIDQuery.swift
//  BadgerKit — BadgerEntity's default query (M4, §11).
//
//  Resolves BadgerEntity values by id (OpenIntent / parameter re-resolution / intent
//  chaining) and suggests the active Badgers. Reads through the injected engine's
//  Sendable snapshot surface — the same @Dependency the intents use, resolved in
//  whatever process runs the query (the SP10 path; verify headless on device).
//

import Foundation

#if os(iOS)
import AppIntents

public struct BadgerByIDQuery: EntityQuery {
    @Dependency public var engine: BadgerEngine

    public init() {}

    public func entities(for identifiers: [UUID]) async throws -> [BadgerEntity] {
        var result: [BadgerEntity] = []
        for id in identifiers {
            if let snap = await engine.snapshot(id: id) { result.append(BadgerEntity(snap)) }
        }
        return result
    }

    /// Zero-input suggestions surface the active Badgers (what the person is likely
    /// acting on) rather than the full history.
    public func suggestedEntities() async throws -> [BadgerEntity] {
        await engine.activeSnapshots().map(BadgerEntity.init)
    }
}
#endif
