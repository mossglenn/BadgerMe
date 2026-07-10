//
//  LadderEntity.swift
//  BadgerKit — the App Intents entity for a reusable ladder template (M4, §11).
//
//  Enables "create a Badger with my {ladder}" once templates are seeded (M7/D10).
//  Minimal in v1: id + name. Value-projected from LadderSnapshot.
//

import Foundation

#if os(iOS)
import AppIntents

public struct LadderEntity: AppEntity {
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Ladder"
    public static var defaultQuery: LadderQuery { LadderQuery() }

    public let id: UUID
    public let name: String

    public init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }

    public init(_ snapshot: LadderSnapshot) { self.init(id: snapshot.id, name: snapshot.name) }

    public var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}
#endif
