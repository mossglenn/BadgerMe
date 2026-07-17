//
//  StraySweep.swift
//  BadgerKit — pure identifier diffs for the backstop stray sweep (§14 Part B, M6 CP2).
//
//  Cold-kill teardown (M3) only reaches alerts a *live* Badger still owns via its persisted
//  refs. If the app is killed mid-arm, a Badger row is deleted out from under its refs, or an
//  AlarmKit id drifts, an orphaned system alarm/notification can fire forever (only an
//  uninstall clears it). On launch the engine's `sweepStrayAlerts()` enumerates what each
//  channel actually has scheduled and cancels anything no non-terminal Badger owns. The
//  attribution differs by channel, so there are two pure diffs — both Foundation-only,
//  value-in/value-out, unit-testable without channels (the pattern of `diffAlarmSnapshot`
//  (M3 #4) and `forwardSlots` (CP1)).
//
//  This also closes the gap CP1 left open: an AlarmKit alarm the OS *dropped* (e.g. across a
//  device restart) is simply absent from the enumerated system set, so a persisted-but-dead
//  ref is a harmless no-op, while a live system alarm no Badger claims is swept.
//

import Foundation

/// Straight set difference: system identifiers not present in `owned`. Used for the AlarmKit
/// channel, whose alarm ids are opaque UUIDs attributable only via the persisted `armedAlarms`
/// of live Badgers (a snapshot `Alarm` carries no metadata — §9/M3). Order-preserving.
func strayIdentifiers(system: [String], owned: Set<String>) -> [String] {
    system.filter { !owned.contains($0) }
}

/// Notification identifiers whose owning Badger (parsed from `badger-{uuid}-…`) is NOT in the
/// live set — i.e. the Badger is terminal or gone. A malformed / foreign id (nil parse) is left
/// ALONE: the sweep only cancels ids it can positively attribute to a dead/absent Badger, never
/// anything it doesn't recognize as its own.
func strayNotificationIdentifiers(system: [String], liveBadgerIDs: Set<UUID>) -> [String] {
    system.filter { id in
        guard let owner = BadgerNotifications.badgerID(fromIdentifier: id) else { return false }
        return !liveBadgerIDs.contains(owner)
    }
}
