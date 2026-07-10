//
//  BadgerLadders.swift
//  BadgerKit — a fallback default ladder for headless create (M4 bridge).
//
//  CreateBadgerIntent needs rungs, which normally come from a chosen LadderEntity
//  (a persisted LadderTemplate). v1 seeds no templates until M7 (D10 — the named
//  Gentle/Default/Urgent presets), so until then create falls back to this constant.
//  Deliberately NOTIFICATION-ONLY: it works without AlarmKit authorization and makes
//  no breakthrough/sound product choices — those are D10's call. Replace with the
//  seeded presets at M7.
//

import Foundation

public enum BadgerLadders {
    /// 3-rung soft escalation at +0s / +5m / +15m. Placeholder until D10 presets.
    public static let defaultRungs: [RungSpec] = [
        RungSpec(index: 0, delay: 0,   actions: [ChannelAction(channelID: "notification", prominence: .active)]),
        RungSpec(index: 1, delay: 300, actions: [ChannelAction(channelID: "notification", prominence: .timeSensitive)]),
        RungSpec(index: 2, delay: 900, actions: [ChannelAction(channelID: "notification", prominence: .timeSensitive)]),
    ]
    public static let defaultMaxSnoozeCount = 2
}
