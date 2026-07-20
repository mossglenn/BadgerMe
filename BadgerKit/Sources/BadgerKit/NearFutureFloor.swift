//
//  NearFutureFloor.swift
//  BadgerKit — minimum future lead times for scheduling (§20 near-future gotcha; B2/SP13).
//
//  A fire date at or just before `now` — e.g. a delay-0 rung 0 created with "start now", or a
//  reconcile catch-up — must still schedule reliably. UserNotifications treats sub-1s / past
//  intervals as unreliable; AlarmKit silently DROPS a `.fixed` alarm whose date is at/before now
//  (observed on device: an alarm first rung at +0 never fires, while a notification first rung at
//  +0 does, because NotificationChannel already clamps). This is the one pure, tested home for that
//  clamp so both channels agree. The exact AlarmKit floor is unmeasured (B2/SP13) — tune `alarm`
//  once measured.
//

import Foundation

enum NearFutureFloor {
    /// UNTimeIntervalNotificationTrigger floor (sub-1s is unreliable).
    static let notification: TimeInterval = 1
    /// Minimum lead for a fixed AlarmKit alarm so an "immediate" alarm still fires.
    static let alarm: TimeInterval = 2

    /// The earliest reliable fire date: `fireDate`, but never sooner than `now + minLead`.
    static func clamp(_ fireDate: Date, now: Date = Date(), minLead: TimeInterval) -> Date {
        max(fireDate, now.addingTimeInterval(minLead))
    }
}
