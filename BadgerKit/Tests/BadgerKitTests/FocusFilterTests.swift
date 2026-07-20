//
//  FocusFilterTests.swift
//  BadgerKitTests — pure Focus-filter cap/scope logic (§13, M6 CP4).
//

import Testing
import Foundation
@testable import BadgerKit

@Suite("BadgerKit Focus filter — pure cap/scope (§13, M6 CP4)")
struct FocusFilterTests {

    // MARK: - Prominence ordering

    @Test("prominence orders passive < active < timeSensitive < breakthrough")
    func prominenceOrder() {
        #expect(Prominence.passive < .active)
        #expect(Prominence.active < .timeSensitive)
        #expect(Prominence.timeSensitive < .breakthrough)
        #expect([Prominence.breakthrough, .passive, .timeSensitive, .active].sorted()
                == [.passive, .active, .timeSensitive, .breakthrough])
    }

    @Test("channel for prominence: breakthrough = alarmkit, softer = notification")
    func channelForProminence() {
        #expect(channelID(forProminence: .breakthrough) == "alarmkit")
        #expect(channelID(forProminence: .timeSensitive) == "notification")
        #expect(channelID(forProminence: .active) == "notification")
        #expect(channelID(forProminence: .passive) == "notification")
    }

    // MARK: - Scope (which Badgers escalate)

    @Test("nil onlyTag lets every Badger escalate")
    func scopeNilLetsAll() {
        #expect(badgerEscalates(focusTags: [], onlyTag: nil))
        #expect(badgerEscalates(focusTags: ["work"], onlyTag: nil))
    }

    @Test("onlyTag holds Badgers that don't carry the tag")
    func scopeTagHoldsOffTag() {
        #expect(badgerEscalates(focusTags: ["work", "urgent"], onlyTag: "work"))
        #expect(!badgerEscalates(focusTags: ["home"], onlyTag: "work"))
        #expect(!badgerEscalates(focusTags: [], onlyTag: "work"))
    }

    // MARK: - Cap (how loud)

    private func action(_ ch: String, _ p: Prominence) -> ChannelAction {
        ChannelAction(channelID: ch, prominence: p, soundRef: .builtIn(id: "klaxon"), message: "hi")
    }

    @Test("nil cap leaves actions unchanged")
    func capNilUnchanged() {
        let a = action("alarmkit", .breakthrough)
        #expect(cappedAction(a, cap: nil) == a)
    }

    @Test("action at or under the cap is unchanged")
    func capAtOrUnderUnchanged() {
        let a = action("notification", .active)
        #expect(cappedAction(a, cap: .timeSensitive) == a)   // under
        #expect(cappedAction(a, cap: .active) == a)          // at
    }

    @Test("breakthrough capped to time-sensitive downgrades AND remaps to notification")
    func capBreakthroughToTimeSensitive() {
        let capped = cappedAction(action("alarmkit", .breakthrough), cap: .timeSensitive)
        #expect(capped.channelID == "notification")
        #expect(capped.prominence == .timeSensitive)
        #expect(capped.soundRef == .builtIn(id: "klaxon"))   // sound/message preserved
        #expect(capped.message == "hi")
    }

    @Test("breakthrough capped to quiet (passive) remaps and downgrades all the way")
    func capBreakthroughToPassive() {
        let capped = cappedAction(action("alarmkit", .breakthrough), cap: .passive)
        #expect(capped.channelID == "notification")
        #expect(capped.prominence == .passive)
    }
}
