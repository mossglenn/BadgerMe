//
//  LadderSnapshot.swift
//  BadgerKit — a Sendable value projection of a LadderTemplate for LadderEntity (M4).
//
//  Same rationale as BadgerSnapshot: the off-actor query layer receives Sendable
//  values, not @Model LadderTemplate instances. v1 ships no seeded templates until M7
//  (D10), so the read path returns [] until then — the type is here so LadderEntity is
//  real now.
//

import Foundation

public struct LadderSnapshot: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let name: String
    public init(id: UUID, name: String) { self.id = id; self.name = name }
}
