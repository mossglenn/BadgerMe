//
//  EngineM4OpsTests.swift
//  BadgerKitTests — the M4 engine surface the App Intents layer drives (§11).
//
//  The catalog's intents are #if os(iOS) (LiveActivityIntent), so they don't run under
//  macOS `swift test`. Their behaviour is the engine methods they call — replace / edit
//  / the snapshot read path — so those are tested here directly, against the in-memory
//  container + FakeChannel, exactly as the intents will invoke them.
//

import Testing
import Foundation
import SwiftData
@testable import BadgerKit

@Suite("BadgerKit engine — M4 App-Intents surface (§11)")
@MainActor
struct EngineM4OpsTests {

    private let T0 = Date(timeIntervalSinceReferenceDate: 0)
    private func at(_ s: TimeInterval) -> Date { T0.addingTimeInterval(s) }

    // rung0 @ +0, rung1 @ +60, rung2 @ +180 (last). Repeat interval = 120.
    private var ladder: [RungSpec] {
        [
            RungSpec(index: 0, delay: 0,   actions: [ChannelAction(channelID: "notification", prominence: .active)]),
            RungSpec(index: 1, delay: 60,  actions: [ChannelAction(channelID: "notification", prominence: .timeSensitive)]),
            RungSpec(index: 2, delay: 180, actions: [ChannelAction(channelID: "notification", prominence: .timeSensitive)]),
        ]
    }

    private func fetchBadger(_ id: UUID, _ c: ModelContainer) -> Badger? {
        var fd = FetchDescriptor<Badger>(predicate: #Predicate { $0.id == id }); fd.fetchLimit = 1
        return (try? c.mainContext.fetch(fd))?.first
    }
    private func eventKinds(_ id: UUID, _ c: ModelContainer) -> [EventKind] {
        let fd = FetchDescriptor<EventRecord>(predicate: #Predicate { $0.badgerID == id },
                                              sortBy: [SortDescriptor(\.sequence)])
        return ((try? c.mainContext.fetch(fd)) ?? []).map(\.kind)
    }

    // MARK: - Read path

    @Test("snapshot(id:) projects the Badger's title / state / level / total rungs")
    func snapshotProjectsFields() async throws {
        var clock = at(0)
        let c = try makeModelContainer(inMemory: true)
        let engine = BadgerEngine(container: c, registry: AlertChannelRegistry([FakeChannel()]),
                                  repeatBatchSize: 2, now: { clock })
        let id = await engine.create(title: "Take meds", notes: "with water",
                                     startAt: at(0), rungs: ladder, maxSnoozeCount: 1)
        clock = at(60)
        await engine.handleForegroundDelivery(badgerID: id)   // reconcile → advances to level 1

        let s = try #require(engine.snapshot(id: id))
        #expect(s.title == "Take meds")
        #expect(s.notes == "with water")
        #expect(s.state == .active)
        #expect(s.currentLevel == 1)
        #expect(s.totalLevels == 3)
        #expect(s.isTerminal == false)
        #expect(s.statusSubtitle == "Escalating — level 2 of 3")
    }

    @Test("snapshot(id:) is nil for an unknown id")
    func snapshotUnknownIsNil() async throws {
        let c = try makeModelContainer(inMemory: true)
        let engine = BadgerEngine(container: c, registry: AlertChannelRegistry([FakeChannel()]))
        #expect(engine.snapshot(id: UUID()) == nil)
    }

    @Test("activeSnapshots excludes terminal; allSnapshots includes everything")
    func activeVsAll() async throws {
        var clock = at(0)
        let c = try makeModelContainer(inMemory: true)
        let engine = BadgerEngine(container: c, registry: AlertChannelRegistry([FakeChannel()]),
                                  repeatBatchSize: 2, now: { clock })
        let a = await engine.create(title: "Alpha", startAt: at(0), rungs: ladder, maxSnoozeCount: 1)
        clock = at(1)
        let b = await engine.create(title: "Bravo", startAt: at(1), rungs: ladder, maxSnoozeCount: 1)
        clock = at(2)
        await engine.markDone(a)

        let active = engine.activeSnapshots().map(\.id)
        let all = engine.allSnapshots().map(\.id)
        #expect(active == [b])                       // a is done → excluded
        #expect(Set(all) == [a, b])
        #expect(all.first == b)                      // newest-first (createdAt desc)
    }

    @Test("snapshots(matchingName:) is a case-insensitive title substring match")
    func matchingName() async throws {
        var clock = at(0)
        let c = try makeModelContainer(inMemory: true)
        let engine = BadgerEngine(container: c, registry: AlertChannelRegistry([FakeChannel()]),
                                  repeatBatchSize: 2, now: { clock })
        let meds = await engine.create(title: "Take MEDS", startAt: at(0), rungs: ladder, maxSnoozeCount: 1)
        clock = at(1)
        _ = await engine.create(title: "Call mom", startAt: at(1), rungs: ladder, maxSnoozeCount: 1)

        #expect(engine.snapshots(matchingName: "meds").map(\.id) == [meds])
        #expect(engine.snapshots(matchingName: "xyz").isEmpty)
    }

    @Test("snapshots(inState:) filters by lifecycle state")
    func inState() async throws {
        var clock = at(0)
        let c = try makeModelContainer(inMemory: true)
        let engine = BadgerEngine(container: c, registry: AlertChannelRegistry([FakeChannel()]),
                                  repeatBatchSize: 2, now: { clock })
        let a = await engine.create(title: "A", startAt: at(0), rungs: ladder, maxSnoozeCount: 1)
        clock = at(1)
        let b = await engine.create(title: "B", startAt: at(1), rungs: ladder, maxSnoozeCount: 1)
        clock = at(2)
        await engine.stop(b)

        #expect(engine.snapshots(inState: .pending).map(\.id) == [a])
        #expect(engine.snapshots(inState: .stopped).map(\.id) == [b])
    }

    // MARK: - Replace (D12)

    @Test("replace re-runs a terminal Badger from a fresh start, re-arming from rung 0")
    func replaceRerunsTerminal() async throws {
        var clock = at(0)
        let c = try makeModelContainer(inMemory: true)
        let fake = FakeChannel()
        let engine = BadgerEngine(container: c, registry: AlertChannelRegistry([fake]),
                                  repeatBatchSize: 2, now: { clock })
        let id = await engine.create(title: "x", startAt: at(0), rungs: ladder, maxSnoozeCount: 1)
        clock = at(30)
        await engine.markDone(id)

        clock = at(1000)
        let s = try #require(await engine.replace(id, startAt: at(1000)))
        #expect(s.state == .pending)
        #expect(s.currentLevel == 0)
        #expect(try #require(fetchBadger(id, c)).startAt == at(1000))
        #expect(eventKinds(id, c).contains(.replaced))
        #expect(await fake.rungSlots == [0, 1, 2])    // re-armed after the done teardown
    }

    @Test("replace is a no-op on a non-terminal Badger")
    func replaceNoOpWhenActive() async throws {
        let clock = at(0)
        let c = try makeModelContainer(inMemory: true)
        let engine = BadgerEngine(container: c, registry: AlertChannelRegistry([FakeChannel()]),
                                  repeatBatchSize: 2, now: { clock })
        let id = await engine.create(title: "x", startAt: at(0), rungs: ladder, maxSnoozeCount: 1)
        let s = try #require(await engine.replace(id, startAt: at(1000)))
        #expect(s.state == .pending)                  // unchanged (was pending)
        #expect(try #require(fetchBadger(id, c)).startAt == at(0))
        #expect(!eventKinds(id, c).contains(.replaced))
    }

    // MARK: - Edit (D2 baseline)

    @Test("edit updates title/notes and re-arms from the current level")
    func editUpdatesAndReArms() async throws {
        var clock = at(0)
        let c = try makeModelContainer(inMemory: true)
        let fake = FakeChannel()
        let engine = BadgerEngine(container: c, registry: AlertChannelRegistry([fake]),
                                  repeatBatchSize: 2, now: { clock })
        let id = await engine.create(title: "old", startAt: at(0), rungs: ladder, maxSnoozeCount: 1)
        clock = at(5)
        let s = try #require(await engine.edit(id, title: "new", notes: "note"))
        #expect(s.title == "new")
        #expect(s.notes == "note")
        #expect(await fake.cancelledAll.contains(id))   // .edited cancels then re-arms
        #expect(await fake.rungSlots == [0, 1, 2])
        #expect(eventKinds(id, c).contains(.edited))
    }

    @Test("edit with a new ladder re-arms against the new rungs")
    func editNewLadder() async throws {
        var clock = at(0)
        let c = try makeModelContainer(inMemory: true)
        let fake = FakeChannel()
        let engine = BadgerEngine(container: c, registry: AlertChannelRegistry([fake]),
                                  repeatBatchSize: 2, now: { clock })
        let id = await engine.create(title: "x", startAt: at(0), rungs: ladder, maxSnoozeCount: 1)
        clock = at(5)
        let twoRung = [
            RungSpec(index: 0, delay: 0,  actions: [ChannelAction(channelID: "notification", prominence: .active)]),
            RungSpec(index: 1, delay: 30, actions: [ChannelAction(channelID: "notification", prominence: .active)]),
        ]
        let s = try #require(await engine.edit(id, rungs: twoRung))
        #expect(s.totalLevels == 2)
        #expect(await fake.rungSlots == [0, 1])         // new ladder has 2 rungs
    }

    @Test("edit is a no-op on a terminal Badger")
    func editNoOpWhenTerminal() async throws {
        var clock = at(0)
        let c = try makeModelContainer(inMemory: true)
        let engine = BadgerEngine(container: c, registry: AlertChannelRegistry([FakeChannel()]),
                                  repeatBatchSize: 2, now: { clock })
        let id = await engine.create(title: "keep", startAt: at(0), rungs: ladder, maxSnoozeCount: 1)
        clock = at(5)
        await engine.markDone(id)
        let s = try #require(await engine.edit(id, title: "changed"))
        #expect(s.title == "keep")                     // unchanged
        #expect(s.state == .done)
        #expect(eventKinds(id, c).filter { $0 == .edited }.isEmpty)
    }
}
