//
//  FocusFilter.swift
//  BadgerKit — pure Focus-filter cap/scope logic (§13, M6 CP4).
//
//  The Focus filter tunes escalation per Focus with two orthogonal controls (§13):
//    • scope  — which Badgers escalate at all (an optional tag; off-tag Badgers are HELD,
//               i.e. not armed, while that Focus is on).
//    • cap    — the maximum prominence any armed action may reach (e.g. Sleep Focus holds
//               hard rungs to soft).
//  Both are applied by the engine at `armSchedule`/`ensureArmed` time (the engine caches the
//  active filter and re-arms live Badgers when it changes). Everything here is pure,
//  Foundation-only, value-in/value-out — unit-tested without the engine or AppIntents (the
//  pattern of StraySweep / ScheduleReplenish / BadgerWidgetSummary). Reducer untouched.
//

import Foundation

/// Prominence order: passive < active < timeSensitive < breakthrough (§10). Lets the cap use
/// `min`/`>` directly.
extension Prominence: Comparable {
    private var rank: Int {
        switch self {
        case .passive:       return 0
        case .active:        return 1
        case .timeSensitive: return 2
        case .breakthrough:  return 3
        }
    }
    public static func < (lhs: Prominence, rhs: Prominence) -> Bool { lhs.rank < rhs.rank }
}

/// The v1 delivery channel that carries a given prominence: breakthrough is AlarmKit, every
/// softer level is a notification (§9/§10). Used when the cap downgrades a breakthrough action
/// — the channel has to move with the prominence (AlarmKit only does breakthrough).
func channelID(forProminence p: Prominence) -> String {
    p == .breakthrough ? "alarmkit" : "notification"
}

/// The active Focus filter's limits (§13). `cap` = max prominence allowed (nil = no cap);
/// `onlyTag` = if set, only Badgers carrying this tag escalate (others held). Cached by the
/// engine and refreshed from the filter intent's `perform()` and `.current` on activation.
struct FocusFilterState: Sendable, Equatable {
    var cap: Prominence?
    var onlyTag: String?
    static let none = FocusFilterState(cap: nil, onlyTag: nil)
}

/// Does a Badger escalate under the current filter? A nil `onlyTag` lets everything through;
/// otherwise the Badger must carry the tag (else it's fully held — the engine arms nothing).
func badgerEscalates(focusTags: [String], onlyTag: String?) -> Bool {
    guard let tag = onlyTag else { return true }
    return focusTags.contains(tag)
}

/// Apply the prominence cap to one action. At/under the cap → unchanged. Above it → downgrade
/// to the cap and remap the channel to whatever delivers it (a breakthrough alarm becomes a
/// time-sensitive/quiet notification), preserving sound / message / payload.
func cappedAction(_ action: ChannelAction, cap: Prominence?) -> ChannelAction {
    guard let cap, action.prominence > cap else { return action }
    return ChannelAction(channelID: channelID(forProminence: cap),
                         prominence: cap,
                         soundRef: action.soundRef,
                         message: action.message,
                         payload: action.payload)
}
