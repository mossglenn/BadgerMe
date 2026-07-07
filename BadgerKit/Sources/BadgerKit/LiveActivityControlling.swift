//
//  LiveActivityControlling.swift
//  BadgerKit — the seam the engine uses for the ambient Live Activity (§12).
//
//  The reducer emits start/update/end Live-Activity effects; the engine forwards
//  them here. In M2 the concrete controller is a no-op: Live Activities land in M5,
//  and keeping this behind a protocol means the package never imports ActivityKit
//  (iOS-only), so `swift test` keeps compiling on macOS. The real ActivityKit-backed
//  controller is added in the app/widget target in M5 and injected at the
//  composition root; this protocol goes public then.
//

import Foundation

/// Manages a Badger's ambient Live Activity (§12). Per-Badger, keyed by id.
protocol LiveActivityControlling: Sendable {
    func start(badgerID: UUID, title: String, phase: ActivityPhase, nextFire: Date?) async
    func update(badgerID: UUID, phase: ActivityPhase, level: Int, nextFire: Date?) async
    func end(badgerID: UUID) async
}

/// M2 stand-in: does nothing. M5 replaces it with an ActivityKit implementation.
struct NoopLiveActivityController: LiveActivityControlling {
    func start(badgerID: UUID, title: String, phase: ActivityPhase, nextFire: Date?) async {}
    func update(badgerID: UUID, phase: ActivityPhase, level: Int, nextFire: Date?) async {}
    func end(badgerID: UUID) async {}
}
