//
//  EngineCP2Tests.swift
//  BadgerKitTests — M7 CP2: built-in preset seeding, the create default-ladder fallback,
//  setFocusTags re-arm under a Focus scope, and BadgerConfig's snooze-option sanitiser.
//  Reuses the top-level FakeChannel from EngineTests.swift; in-memory container, injected clock.
//

import Testing
import Foundation
import SwiftData
@testable import BadgerKit

@MainActor
@Suite("BadgerKit engine — M7 CP2 (seed + default ladder + focus tags)")
struct EngineCP2Tests {

    private let T0 = Date(timeIntervalSinceReferenceDate: 0)
    private func at(_ s: TimeInterval) -> Date { T0.addingTimeInterval(s) }

    private let ladder = [
        RungSpec(index: 0, delay: 0,   actions: [ChannelAction(channelID: "notification", prominence: .active)]),
        RungSpec(index: 1, delay: 60,  actions: [ChannelAction(channelID: "notification", prominence: .timeSensitive)]),
        RungSpec(index: 2, delay: 120, actions: [ChannelAction(channelID: "notification", prominence: .timeSensitive)]),
    ]

    private func makeEngine(_ c: ModelContainer, _ fake: FakeChannel) -> BadgerEngine {
        BadgerEngine(container: c, registry: AlertChannelRegistry([fake]),
                     repeatBatchSize: 1, now: { self.T0 })
    }

    // MARK: - Seeding

    @Test("seedBuiltInLadders is idempotent and populates the read side")
    func seedIdempotent() async throws {
        let c = try makeModelContainer(inMemory: true)
        let engine = makeEngine(c, FakeChannel())

        engine.seedBuiltInLadders()
        engine.seedBuiltInLadders()   // second run must not duplicate

        let snaps = engine.ladderTemplateSnapshots()
        #expect(snaps.count == 3)
        #expect(snaps.map(\.name) == ["Default", "Gentle", "Urgent"])   // sorted by name
        // The Default template resolves to the balanced preset's rungs.
        let resolved = try #require(engine.ladderRungs(templateID: LadderPresets.defaultID))
        #expect(resolved.rungs == LadderPresets.balanced.rungs)
        #expect(resolved.maxSnoozeCount == LadderPresets.balanced.defaultMaxSnoozeCount)
    }

    // MARK: - Default ladder fallback

    @Test("defaultLadder falls back to the Default preset when nothing is seeded")
    func defaultLadderFallback() async throws {
        let c = try makeModelContainer(inMemory: true)
        let engine = makeEngine(c, FakeChannel())
        let d = engine.defaultLadder()   // no templates exist → balanced fallback
        #expect(d.rungs == LadderPresets.balanced.rungs)
        #expect(d.maxSnoozeCount == LadderPresets.balanced.defaultMaxSnoozeCount)
    }

    @Test("defaultLadder resolves the seeded Default template once seeded")
    func defaultLadderResolvesSeeded() async throws {
        let c = try makeModelContainer(inMemory: true)
        let engine = makeEngine(c, FakeChannel())
        engine.seedBuiltInLadders()
        #expect(engine.defaultLadder().rungs == LadderPresets.balanced.rungs)
    }

    // MARK: - setFocusTags

    @Test("setFocusTags sanitises input and re-arms a held Badger under an active scope")
    func setFocusTagsReArms() async throws {
        let c = try makeModelContainer(inMemory: true)
        let notif = FakeChannel()
        let engine = makeEngine(c, notif)

        let id = await engine.create(title: "b", startAt: at(0), rungs: ladder, maxSnoozeCount: 1)
        // A scope for "work" holds this untagged Badger: its pending alerts are cleared.
        await engine.applyFocusFilter(cap: nil, onlyTag: "work")
        #expect(!(await notif.scheduled.contains { $0.badgerID == id }))

        // Messy input: trimmed, de-duplicated, empties dropped.
        await engine.setFocusTags([" work ", "work", ""], on: id)
        #expect(engine.allFocusTags() == ["work"])
        #expect(await notif.scheduled.contains { $0.badgerID == id })   // now tagged → re-armed
    }

    // MARK: - BadgerConfig snooze-option sanitiser (pure)

    @Test("sanitizedSnoozeOptions drops non-positive, de-dupes, sorts; empty → fallback")
    func snoozeOptionSanitiser() {
        #expect(BadgerConfig.sanitizedSnoozeOptions([15, 5, 15, -3, 0, 9]) == [5, 9, 15])
        #expect(BadgerConfig.sanitizedSnoozeOptions([]) == BadgerConfig.fallbackSnoozeOptions)
        #expect(BadgerConfig.sanitizedSnoozeOptions([-1, 0]) == BadgerConfig.fallbackSnoozeOptions)
    }

    // MARK: - Re-snooze no-op (D6 clarification, M7)

    @Test("snoozing an already-snoozed Badger is a no-op — no extra event, no snoozeCount bump")
    func reSnoozeIsNoOp() async throws {
        let c = try makeModelContainer(inMemory: true)
        let engine = makeEngine(c, FakeChannel())
        let id = await engine.create(title: "b", startAt: at(0), rungs: ladder, maxSnoozeCount: 1)

        await engine.snooze(id, duration: 120)
        #expect(fetchBadger(id, c)?.state == .snoozed)
        let count1 = fetchBadger(id, c)?.snoozeCount
        #expect(count1 == 1)
        #expect(snoozeEventCount(id, c) == 1)

        await engine.snooze(id, duration: 120)     // already snoozed → ignored
        #expect(fetchBadger(id, c)?.state == .snoozed)
        #expect(fetchBadger(id, c)?.snoozeCount == count1)   // not bumped
        #expect(snoozeEventCount(id, c) == 1)                // still exactly one userSnoozed
    }

    private func fetchBadger(_ id: UUID, _ c: ModelContainer) -> Badger? {
        var fd = FetchDescriptor<Badger>(predicate: #Predicate { $0.id == id })
        fd.fetchLimit = 1
        return (try? ModelContext(c).fetch(fd))?.first
    }

    private func snoozeEventCount(_ id: UUID, _ c: ModelContainer) -> Int {
        let all = (try? ModelContext(c).fetch(FetchDescriptor<EventRecord>())) ?? []
        return all.filter { $0.badgerID == id && $0.kindRaw == "userSnoozed" }.count
    }
}
