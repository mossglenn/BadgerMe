//
//  EngineTemplateTests.swift
//  BadgerKitTests — M7 CP4a: user ladder-template create/update/delete, with built-ins protected.
//  Reuses the top-level FakeChannel; in-memory container, @MainActor (engine is main-actor).
//

import Testing
import Foundation
import SwiftData
@testable import BadgerKit

@MainActor
@Suite("BadgerKit engine — M7 CP4a (ladder template CRUD)")
struct EngineTemplateTests {

    private func makeEngine(_ c: ModelContainer) -> BadgerEngine {
        BadgerEngine(container: c, registry: AlertChannelRegistry([FakeChannel()]),
                     repeatBatchSize: 1, now: { Date(timeIntervalSinceReferenceDate: 0) })
    }

    /// Out-of-order indices with a fixed array order [300, 60]; save must ignore the given indices
    /// and re-index by POSITION, preserving array order (D8: incremental gaps are not delay-sorted).
    private let messyRungs = [
        RungSpec(index: 5, delay: 300, actions: [ChannelAction(channelID: "notification", prominence: .active)]),
        RungSpec(index: 2, delay: 60,  actions: [ChannelAction(channelID: "notification", prominence: .timeSensitive)]),
    ]

    @Test("saveTemplate preserves array order and re-indexes 0..n (no delay sort)")
    func createPreservesOrderAndReindexes() async throws {
        let c = try makeModelContainer(inMemory: true)
        let engine = makeEngine(c)
        let id = engine.saveTemplate(name: "Mine", rungs: messyRungs, maxSnoozeCount: 2)

        let r = try #require(engine.ladderRungs(templateID: id))
        #expect(r.rungs.map(\.index) == [0, 1])
        #expect(r.rungs.map(\.delay) == [300, 60])   // array order preserved, NOT delay-sorted
        #expect(r.maxSnoozeCount == 2)
        #expect(engine.ladderTemplateSnapshots().contains { $0.id == id && $0.name == "Mine" })
    }

    @Test("saveTemplate updates an existing template in place (no duplicate)")
    func updateInPlace() async throws {
        let c = try makeModelContainer(inMemory: true)
        let engine = makeEngine(c)
        let id = engine.saveTemplate(name: "A", rungs: messyRungs, maxSnoozeCount: 1)
        let before = engine.ladderTemplateSnapshots().count

        engine.saveTemplate(id: id, name: "B", rungs: messyRungs, maxSnoozeCount: 3)
        #expect(engine.ladderTemplateSnapshots().count == before)
        #expect(engine.ladderTemplateSnapshots().first { $0.id == id }?.name == "B")
        #expect(engine.ladderRungs(templateID: id)?.maxSnoozeCount == 3)
    }

    @Test("built-in templates are read-only: save/delete targeting one is a no-op")
    func builtInsProtected() async throws {
        let c = try makeModelContainer(inMemory: true)
        let engine = makeEngine(c)
        engine.seedBuiltInLadders()

        engine.saveTemplate(id: LadderPresets.defaultID, name: "Hacked",
                            rungs: messyRungs, maxSnoozeCount: 9)
        #expect(engine.ladderTemplateSnapshots().first { $0.id == LadderPresets.defaultID }?.name == "Default")
        #expect(engine.ladderRungs(templateID: LadderPresets.defaultID)?.rungs == LadderPresets.balanced.rungs)

        engine.deleteTemplate(id: LadderPresets.defaultID)
        #expect(engine.ladderRungs(templateID: LadderPresets.defaultID) != nil)   // still present
    }

    @Test("deleteTemplate removes a user template")
    func deleteUserTemplate() async throws {
        let c = try makeModelContainer(inMemory: true)
        let engine = makeEngine(c)
        let id = engine.saveTemplate(name: "Temp", rungs: messyRungs, maxSnoozeCount: 1)
        engine.deleteTemplate(id: id)
        #expect(engine.ladderRungs(templateID: id) == nil)
    }
}
