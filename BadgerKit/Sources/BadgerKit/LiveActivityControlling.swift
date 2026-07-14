//
//  LiveActivityControlling.swift
//  BadgerKit — the seam the engine uses for the ambient Live Activity (§12).
//
//  The reducer emits start/update/end Live-Activity effects; the engine forwards them here.
//  Kept behind a protocol so the engine/reducer core never imports ActivityKit and `swift
//  test` keeps compiling on macOS. The protocol and its conformers all live in BadgerKit and
//  stay INTERNAL for now. The phase is the public Foundation-only `BadgerActivityPhase`
//  (shared with the widget as `BadgerActivityAttributes.Phase`), so the reducer emits it
//  directly and the real ActivityKit controller (M5 CP2b, guarded #if os(iOS)) sets it
//  straight onto ContentState — no translation. A public protocol + composition-root
//  injection is the follow-up (code review #9).
//
//  `level`/`totalLevels` are passed in (not looked up) so the conformer stays stateless and
//  needs no ModelContainer: the engine already holds the bound ladder at dispatch time and
//  sources `totalLevels` from `ctx.rungs.count` (§12 "k of n").
//

import Foundation

/// Manages a Badger's ambient Live Activity (§12). Per-Badger, keyed by id.
protocol LiveActivityControlling: Sendable {
    func start(badgerID: UUID, title: String, tint: String?, iconName: String?, phase: BadgerActivityPhase,
               level: Int, totalLevels: Int, nextFire: Date?) async
    func update(badgerID: UUID, phase: BadgerActivityPhase,
                level: Int, totalLevels: Int, nextFire: Date?) async
    func end(badgerID: UUID, terminalPhase: BadgerActivityPhase?) async
}

/// Stand-in used on macOS and until the real controller is wired (CP2b): does nothing.
struct NoopLiveActivityController: LiveActivityControlling {
    func start(badgerID: UUID, title: String, tint: String?, iconName: String?, phase: BadgerActivityPhase,
               level: Int, totalLevels: Int, nextFire: Date?) async {}
    func update(badgerID: UUID, phase: BadgerActivityPhase,
                level: Int, totalLevels: Int, nextFire: Date?) async {}
    func end(badgerID: UUID, terminalPhase: BadgerActivityPhase?) async {}
}
