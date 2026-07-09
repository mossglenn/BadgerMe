//
//  AlertChannel.swift
//  BadgerKit — the AlertChannel protocol + registry (Phase 5 §9, goal 3 spine).
//
//  The engine never names a system API directly; it emits ChannelActions that the
//  registry routes to a conforming channel (L4). New alert *kinds* = new conformers
//  + a registry entry; the engine and reducer don't change. The protocol is Sendable
//  with Sendable params/returns so the `@MainActor` engine can await a channel across
//  the actor boundary without data-race diagnostics.
//

import Foundation

/// Recurrence a channel can express natively. Per SP3 (2026-07-06) no v1 channel
/// supports an arbitrary interval — AlarmKit's only native recurrence is weekly
/// wall-clock — so v1 delivery never uses this and the last-rung repeat is always a
/// replenished batch (§10). Kept so `schedule` stays faithful to §9 and future
/// recurring Badgers (D12) have a shape to fill in.
public enum ChannelRecurrence: Sendable, Equatable {
    case weeklyWallClock(weekdays: [Int])   // 1 = Sunday … 7 = Saturday
}

/// Where a scheduled item sits in a Badger's ladder. A shared vocabulary so the
/// engine and every channel agree on identity without a channel-specific scheme.
public enum ScheduleSlot: Sendable, Equatable, Hashable, Codable {
    case rung(Int)                          // a base rung's fire
    case repeatTail(rung: Int, n: Int)      // the nth repeat of the last rung (§8/§10)
    case wake                               // a snooze-expiry nudge (armWake)
}

/// A persisted, addressable reference to one armed alert: its platform identifier plus
/// the `ScheduleSlot` it fills. Stored on `Badger`, so it survives process termination
/// and teardown can cancel prior-process alarms after a cold kill (M3 cold-kill fix).
public struct ArmedRef: Codable, Equatable, Sendable {
    public let id: String          // AlarmKit alarm UUID (as string)
    public let slot: ScheduleSlot  // typed identity
    public init(id: String, slot: ScheduleSlot) {
        self.id = id
        self.slot = slot
    }
}

/// A cancellable handle to something a channel scheduled (§9). Concrete (not an
/// associated type) so the registry can hold `any AlertChannel`. `identifier` is the
/// channel's native id — a UNNotificationRequest id, or an AlarmKit alarm UUID string.
public struct ScheduledRef: Sendable, Equatable {
    public let channelID: String
    public let identifier: String
    public let slot: ScheduleSlot
    public init(channelID: String, identifier: String, slot: ScheduleSlot) {
        self.channelID = channelID
        self.identifier = identifier
        self.slot = slot
    }
}

/// A live transition a channel observed (§9 `observe`, §14 path 1). The channel does
/// any snapshot-diffing internally (AlarmKit emits full array snapshots, not deltas,
/// and each snapshot `Alarm` carries no metadata — §9/M3) and yields these so the
/// engine maps them onto reducer events. Carries `badgerID` because a channel's
/// observe stream is app-global (one `AlarmManager.alarmUpdates` covers every Badger),
/// so the event must name which Badger it belongs to; the channel recovers the
/// (badgerID, rung) identity from an internal map it builds at `schedule` time.
public enum ChannelEvent: Sendable, Equatable {
    case levelFired(badgerID: UUID, rung: Int)
    case repeatFired(badgerID: UUID, rung: Int, n: Int)
    case dismissed(badgerID: UUID, rung: Int)
}

/// What a channel can do (§9). Every v1 channel declares
/// `supportsArbitraryRecurrence == false` (SP3).
public struct ChannelCapabilities: Sendable, Equatable {
    public let prominences: Set<Prominence>
    public let deliversInBackground: Bool
    public let observableAtFire: Bool
    public let needsWidget: Bool
    public let supportsArbitraryRecurrence: Bool
    public init(prominences: Set<Prominence>, deliversInBackground: Bool,
                observableAtFire: Bool, needsWidget: Bool,
                supportsArbitraryRecurrence: Bool) {
        self.prominences = prominences
        self.deliversInBackground = deliversInBackground
        self.observableAtFire = observableAtFire
        self.needsWidget = needsWidget
        self.supportsArbitraryRecurrence = supportsArbitraryRecurrence
    }
}

/// A delivery mechanism the engine talks to instead of a system API (L4/§9).
public protocol AlertChannel: Sendable {
    var id: String { get }
    var capabilities: ChannelCapabilities { get }

    /// Schedule one action at a fire date in a Badger's ladder slot; return a
    /// cancellable ref. `recurrence` is nil in v1 (SP3).
    func schedule(_ action: ChannelAction, at fireDate: Date,
                  recurrence: ChannelRecurrence?, badgerID: UUID,
                  slot: ScheduleSlot) async throws -> ScheduledRef

    /// Cancel one previously-scheduled item.
    func cancel(_ ref: ScheduledRef) async

    /// Cancel everything this channel scheduled for a Badger (teardown / re-arm).
    func cancelAll(forBadgerID badgerID: UUID) async

    /// Cancel specific items by their platform identifiers. Unlike `cancelAll(forBadgerID:)`,
    /// this needs no in-memory/live state, so it works after a cold kill from the persisted
    /// `armedAlarms` (M3 cold-kill fix). Default: no-op (channels that tear down by namespace
    /// — notifications — rely on `cancelAll(forBadgerID:)` instead).
    func cancel(identifiers: [String]) async

    /// Repopulate any in-memory owner/identity map from persisted armed refs, so
    /// `observe()` can attribute firings of items armed in a prior process after a
    /// relaunch (M3 cold-kill fix). Default: no-op (channels with no live owner map).
    func adopt(badgerID: UUID, refs: [ArmedRef]) async

    /// Live transitions while the app runs, or nil if the channel isn't observable at
    /// fire (notifications; §9). AlarmKit returns a real stream in M3.
    func observe() -> AsyncStream<ChannelEvent>?
}

public extension AlertChannel {
    /// Default: no-op. Overridden by channels that support id-targeted cancellation
    /// (AlarmKit) or namespace-based removal (notifications).
    func cancel(identifiers: [String]) async {}

    /// Default: no-op. Overridden by channels with a live owner map (AlarmKit).
    func adopt(badgerID: UUID, refs: [ArmedRef]) async {}
}

public extension AlertChannel {
    func observe() -> AsyncStream<ChannelEvent>? { nil }
}

/// The channel registry (§9): resolve a `ChannelAction.channelID` to a channel. An
/// unregistered id resolves to nil; the engine logs and skips it (so a breakthrough
/// rung is inert until M3 registers `alarmkit`, never a crash).
public struct AlertChannelRegistry: Sendable {
    private var channels: [String: any AlertChannel]
    public init(_ channels: [any AlertChannel] = []) {
        self.channels = Dictionary(channels.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
    }
    public mutating func register(_ channel: any AlertChannel) {
        channels[channel.id] = channel
    }
    public func channel(for id: String) -> (any AlertChannel)? { channels[id] }
    public var allChannels: [any AlertChannel] { Array(channels.values) }
}
