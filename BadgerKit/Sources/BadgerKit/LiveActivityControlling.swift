//
//  LiveActivityControlling.swift
//  BadgerKit — the seam the engine uses for the ambient Live Activity (§12).
//
//  The reducer emits start/update/end Live-Activity effects; the engine forwards them here.
//  Kept behind a protocol so the engine/reducer core never imports ActivityKit and `swift
//  test` keeps compiling on macOS. The protocol and its conformers all live in BadgerKit and
//  stay INTERNAL — the reducer's `ActivityPhase` is internal to the locked core, so a public
//  protocol can't expose it; the real ActivityKit controller (M5 CP2b, guarded
//  #if os(iOS)) lives here too and maps `ActivityPhase` onto the public
//  `BadgerActivityAttributes.Phase` when it builds the ContentState.
//
//  `level`/`totalLevels` are passed in (not looked up) so the conformer stays stateless and
//  needs no ModelContainer: the engine already holds the bound ladder at dispatch time and
//  sources `totalLevels` from `ctx.rungs.count` (§12 "k of n").
//

import Foundation

/// Manages a Badger's ambient Live Activity (§12). Per-Badger, keyed by id.
protocol LiveActivityControlling: Sendable {
    func start(badgerID: UUID, title: String, phase: ActivityPhase,
               level: Int, totalLevels: Int, nextFire: Date?) async
    func update(badgerID: UUID, phase: ActivityPhase,
                level: Int, totalLevels: Int, nextFire: Date?) async
    func end(badgerID: UUID) async
}

/// Stand-in used on macOS and until the real controller is wired (CP2b): does nothing.
struct NoopLiveActivityController: LiveActivityControlling {
    func start(badgerID: UUID, title: String, phase: ActivityPhase,
               level: Int, totalLevels: Int, nextFire: Date?) async {}
    func update(badgerID: UUID, phase: ActivityPhase,
                level: Int, totalLevels: Int, nextFire: Date?) async {}
    func end(badgerID: UUID) async {}
}
