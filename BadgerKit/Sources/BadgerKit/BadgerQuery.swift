//
//  BadgerQuery.swift
//  BadgerKit — BadgerEntity's default query (M4, §11).
//
//  App Intents resolves a `@Parameter var badger: BadgerEntity` through the entity's
//  single `defaultQuery`, so the spec's separate BadgerByID/String/Property queries
//  collapse into one type here (reconciled in §11 at M4 close): this conforms to
//  EntityStringQuery (id resolution for OpenIntent / parameter re-resolution / chaining,
//  AND spoken/typed-name matching for Siri/Shortcuts) and EnumerableEntityQuery (full
//  picker enumeration). Property-based Find (EntityPropertyQuery) is deferred for v1 —
//  it needs @Property-wrapped entity fields + comparator mapping for a Shortcuts
//  "Find where state is…" nicety; state filtering is available via GetActiveBadgersIntent
//  and the engine's snapshot(inState:) surface.
//
//  Reads through the injected engine's Sendable snapshot surface — the same @Dependency
//  the intents use, resolved in whatever process runs the query (the SP10 path).
//

import Foundation

#if os(iOS)
import AppIntents

public struct BadgerQuery: EntityStringQuery, EnumerableEntityQuery {
    @Dependency public var engine: BadgerEngine

    public init() {}

    /// Resolve by id (OpenIntent / parameter re-resolution / chaining).
    public func entities(for identifiers: [UUID]) async throws -> [BadgerEntity] {
        var result: [BadgerEntity] = []
        for id in identifiers {
            if let snap = await engine.snapshot(id: id) { result.append(BadgerEntity(snap)) }
        }
        return result
    }

    /// Resolve by spoken/typed name (case-insensitive title substring).
    public func entities(matching string: String) async throws -> [BadgerEntity] {
        await engine.snapshots(matchingName: string).map(BadgerEntity.init)
    }

    /// Full enumeration for Shortcuts pickers (all states, newest-first).
    public func allEntities() async throws -> [BadgerEntity] {
        await engine.allSnapshots().map(BadgerEntity.init)
    }

    /// Zero-input suggestions surface the ACTIVE Badgers (what the person is likely
    /// acting on) rather than the full history — overrides the enumerable default.
    public func suggestedEntities() async throws -> [BadgerEntity] {
        await engine.activeSnapshots().map(BadgerEntity.init)
    }
}
#endif
