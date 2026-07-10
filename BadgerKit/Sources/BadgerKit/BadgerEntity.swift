//
//  BadgerEntity.swift
//  BadgerKit — the App Intents entity for a Badger (M4, §11, headless-first L3).
//
//  A value AppEntity projected from a BadgerSnapshot (the engine hands back Sendable
//  values, never @Model instances — see BadgerSnapshot). `id` is the Badger's UUID:
//  UUID conforms to EntityIdentifierConvertible on the 26.5 SDK, so no string identity
//  is needed. IndexedEntity is satisfied via `attributeSet` (the shipping API — the
//  spec's "indexingKey" predates it; reconciled in §11), indexing title + notes for
//  Spotlight semantic search.
//
//  iOS-only (matches the App Intents surface convention) so BadgerKit keeps compiling
//  on macOS for `swift test`; the engine read path it projects from is tested there.
//

import Foundation

#if os(iOS)
import AppIntents
import CoreSpotlight

public struct BadgerEntity: AppEntity, IndexedEntity {
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Badger"
    public static var defaultQuery: BadgerQuery { BadgerQuery() }

    public let id: UUID
    public let title: String
    public let notes: String?
    public let statusSubtitle: String
    public let iconName: String?

    public init(id: UUID, title: String = "", notes: String? = nil,
                statusSubtitle: String = "", iconName: String? = nil) {
        self.id = id
        self.title = title
        self.notes = notes
        self.statusSubtitle = statusSubtitle
        self.iconName = iconName
    }

    /// The channel/button construction site holds only the UUID; the display fields
    /// are refreshed when App Intents re-resolves the parameter through the query.
    public init(id: UUID) { self.init(id: id, title: "") }

    public init(_ snapshot: BadgerSnapshot) {
        self.init(id: snapshot.id, title: snapshot.title, notes: snapshot.notes,
                  statusSubtitle: snapshot.statusSubtitle, iconName: snapshot.iconName)
    }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: statusSubtitle.isEmpty ? nil : "\(statusSubtitle)",
            image: iconName.map { DisplayRepresentation.Image(systemName: $0) })
    }

    /// Index title + notes for Spotlight semantic search (§11).
    public var attributeSet: CSSearchableItemAttributeSet {
        let set = defaultAttributeSet
        set.title = title
        set.contentDescription = notes
        set.keywords = [title]
        return set
    }
}
#endif
