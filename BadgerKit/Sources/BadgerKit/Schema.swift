//
//  Schema.swift
//  BadgerKit — versioned schema + migration plan + container factory (L13, §6, §21-M0).
//

import Foundation
import SwiftData

/// The initial versioned schema (L13). `models` is the single source of truth.
enum BadgerSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [Badger.self, LadderTemplate.self, BoundLadder.self, EventRecord.self]
    }
}

/// Migration plan wired in from day one so the first real stage is a tested addition
/// rather than a data-loss emergency (§6). No stages yet (V1 only).
enum BadgerMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [BadgerSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

/// Builds the ModelContainer against the versioned schema + migration plan.
/// Tests pass `inMemory: true`; the app passes the App-Group id so the widget and
/// intents can read Badger state without the app running (§4). Public: the app's
/// composition root calls this.
public func makeModelContainer(inMemory: Bool = false,
                               groupContainerID: String? = nil) throws -> ModelContainer {
    let schema = Schema(versionedSchema: BadgerSchemaV1.self)
    let configuration: ModelConfiguration
    if inMemory {
        configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    } else if let id = groupContainerID {
        configuration = ModelConfiguration(schema: schema, groupContainer: .identifier(id))
    } else {
        configuration = ModelConfiguration(schema: schema)
    }
    return try ModelContainer(for: schema,
                              migrationPlan: BadgerMigrationPlan.self,
                              configurations: configuration)
}
