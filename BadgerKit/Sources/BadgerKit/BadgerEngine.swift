//
//  BadgerEngine.swift
//  BadgerKit — the impure core: runs reducer effects, persists, drives channels (§5/§8).
//
//  The engine is the only impure part (I/O, scheduling, persistence). It dispatches
//  an Event to the pure reducer, applies the new state to the Badger cache, executes
//  the emitted effects (schedule/cancel via the AlertChannel registry; append to the
//  event log; Live-Activity via the injected controller), and saves. It talks ONLY to
//  the AlertChannel protocol — never a system API directly — so it imports no
//  UserNotifications/AlarmKit and stays unit-testable with fake channels (§18).
//
//  @MainActor because SwiftData's ModelContext is main-actor-bound; this is also the
//  L11 composition root that M4's App-Intents @Dependency will wrap. (Concurrent
//  dispatches are not expected in v1 — the console/intents drive it serially; a
//  production serial executor would harden the sequence counter across awaits.)
//

import Foundation
import SwiftData

@MainActor
public final class BadgerEngine {
    private let container: ModelContainer
    private var registry: AlertChannelRegistry
    private let liveActivity: any LiveActivityControlling
    private let now: () -> Date

    /// Tasks consuming each observable channel's `observe()` stream (§14 path 1).
    /// Retained so they live as long as the engine.
    private var observationTasks: [Task<Void, Never>] = []

    /// Per-Badger repeat batch size for a soft last rung (§10). Bounded by the
    /// 64-pending-per-app budget shared across ~D3 concurrent Badgers; the batch is
    /// replenished on reconcile (M6). SP3: never a single recurring notification.
    private let repeatBatchSize: Int

    private var context: ModelContext { container.mainContext }

    public init(container: ModelContainer,
                registry: AlertChannelRegistry,
                repeatBatchSize: Int = 16,
                now: @escaping () -> Date = { Date() }) {
        self.container = container
        self.registry = registry
        self.liveActivity = NoopLiveActivityController()   // real ActivityKit impl injected in M5
        self.repeatBatchSize = repeatBatchSize
        self.now = now
    }

    // MARK: - Public operations (the surface M4's intents will call)

    @discardableResult
    public func create(title: String, notes: String? = nil, startAt: Date,
                       rungs: [RungSpec], maxSnoozeCount: Int,
                       tint: String = "accent", iconName: String? = nil,
                       source: TriggerSource = .manual) async -> UUID {
        let ladder = BoundLadder(rungs: rungs.sorted { $0.index < $1.index })
        let badger = Badger(title: title, notes: notes, createdAt: now(), startAt: startAt,
                            source: source, maxSnoozeCount: maxSnoozeCount,
                            tint: tint, iconName: iconName, ladder: ladder)
        context.insert(badger)
        await dispatch(.created(startAt: startAt), to: badger)
        return badger.id
    }

    public func markDone(_ id: UUID) async { await dispatch(.userMarkedDone, toBadgerID: id) }
    public func snooze(_ id: UUID, duration: TimeInterval) async {
        await dispatch(.userSnoozed(duration: duration), toBadgerID: id)
    }
    public func stop(_ id: UUID) async { await dispatch(.userStopped, toBadgerID: id) }
    public func markAlarmDismissed(_ id: UUID, rung: Int) async {
        await dispatch(.alarmDismissed(level: rung), toBadgerID: id)
    }

    /// Hard-delete the Badger and its event log (D5), after tearing down its alerts.
    public func delete(_ id: UUID) async {
        guard let badger = fetch(id) else { return }
        await cancelPending(for: badger)
        await liveActivity.end(badgerID: id)
        let events = (try? context.fetch(FetchDescriptor<EventRecord>(
            predicate: #Predicate { $0.badgerID == id }))) ?? []
        for e in events { context.delete(e) }
        context.delete(badger)
        try? context.save()
    }

    /// Notification response routing (delegate -> engine). Done/Snooze resolve; any
    /// other id (body tap / dismiss) just reconciles that Badger.
    public func handleNotificationResponse(badgerID: UUID, actionID: String,
                                           defaultSnooze: TimeInterval) async {
        switch actionID {
        case BadgerNotifications.doneActionID:   await markDone(badgerID)
        case BadgerNotifications.snoozeActionID: await snooze(badgerID, duration: defaultSnooze)
        default:                                  await reconcile(badgerID)
        }
    }

    /// A notification fired while the app is foreground: advance that Badger now.
    public func handleForegroundDelivery(badgerID: UUID) async { await reconcile(badgerID) }

    /// Foreground catch-up over all live Badgers (§14; basic — full replenish/restart
    /// handling is M6). Uses the same pure reconcile the reducer defines.
    public func reconcileAll() async {
        let all = (try? context.fetch(FetchDescriptor<Badger>())) ?? []
        for badger in all where !isTerminal(badger.state) { await runReconcile(on: badger) }
    }

    public func reconcile(_ id: UUID) async {
        guard let badger = fetch(id), !isTerminal(badger.state) else { return }
        await runReconcile(on: badger)
    }

    // MARK: - Replace / Edit (M4 — the mutation ops the intent catalog needs)

    /// Re-run a terminal Badger from its bound ladder at a fresh start (D12, §8/§11).
    /// No-op on a non-terminal Badger (the reducer guards `.replace`). Returns the
    /// refreshed snapshot, or nil if the id is unknown.
    @discardableResult
    public func replace(_ id: UUID, startAt: Date? = nil) async -> BadgerSnapshot? {
        guard let badger = fetch(id) else { return nil }
        await dispatch(.replace(startAt: startAt ?? now()), to: badger)
        return snapshot(of: badger)
    }

    /// Edit a live Badger (D2 baseline: title/notes freely; a schedule change re-arms).
    /// Any nil argument leaves that field unchanged. The model is mutated BEFORE
    /// dispatching `.edited`, so the reducer's cancel + re-arm-from-current-level runs
    /// against the NEW ladder/context. No-op on a terminal Badger (the reducer guards
    /// `.edited`). v1 note: `notes` cannot be CLEARED here (nil == unchanged); a
    /// dedicated clear is deferred with D2.
    @discardableResult
    public func edit(_ id: UUID, title: String? = nil, notes: String? = nil,
                     rungs: [RungSpec]? = nil, maxSnoozeCount: Int? = nil,
                     tint: String? = nil, iconName: String? = nil) async -> BadgerSnapshot? {
        guard let badger = fetch(id) else { return nil }
        guard !isTerminal(badger.state) else { return snapshot(of: badger) }
        if let title { badger.title = title }
        if let notes { badger.notes = notes }
        if let maxSnoozeCount { badger.maxSnoozeCount = maxSnoozeCount }
        if let tint { badger.tint = tint }
        if let iconName { badger.iconName = iconName }
        if let rungs { badger.ladder = BoundLadder(rungs: rungs.sorted { $0.index < $1.index }) }
        await dispatch(.edited, to: badger)
        return snapshot(of: badger)
    }

    // MARK: - Read path (M4 — feeds BadgerEntity + the entity queries, §11)

    /// One Badger by id, projected to a Sendable snapshot.
    public func snapshot(id: UUID) -> BadgerSnapshot? { fetch(id).map { snapshot(of: $0) } }

    /// Every Badger (any state), newest first.
    public func allSnapshots() -> [BadgerSnapshot] { fetchAll().map { snapshot(of: $0) } }

    /// Non-terminal Badgers (pending / active / snoozed) — "what's badgering me"
    /// (GetActiveBadgersIntent) and the BadgerPropertyQuery "active" filter.
    public func activeSnapshots() -> [BadgerSnapshot] {
        fetchAll().filter { !isTerminal($0.state) }.map { snapshot(of: $0) }
    }

    /// Case-insensitive title substring match (backs BadgerStringQuery).
    public func snapshots(matchingName name: String) -> [BadgerSnapshot] {
        let needle = name.lowercased()
        return fetchAll().filter { $0.title.lowercased().contains(needle) }.map { snapshot(of: $0) }
    }

    /// All Badgers in a given lifecycle state (backs BadgerPropertyQuery).
    public func snapshots(inState state: StoredBadgerState) -> [BadgerSnapshot] {
        fetchAll().filter { $0.state == state }.map { snapshot(of: $0) }
    }

    /// Reusable ladder templates as Sendable snapshots (backs LadderEntity/LadderQuery).
    /// Empty until M7 seeds the named presets (D10).
    public func ladderTemplateSnapshots() -> [LadderSnapshot] {
        var fd = FetchDescriptor<LadderTemplate>()
        fd.sortBy = [SortDescriptor(\.name)]
        return ((try? context.fetch(fd)) ?? []).map { LadderSnapshot(id: $0.id, name: $0.name) }
    }

    // MARK: - Channel observation (§14 path 1)

    /// Start consuming the live transition stream of every observable channel
    /// (AlarmKit in M3). Each yielded ChannelEvent is mapped onto a reducer event and
    /// dispatched to its Badger. Call once at composition-root startup, after channels
    /// are registered. Notifications aren't observable (observe() == nil), so in v1
    /// this is effectively the AlarmKit path.
    /// Rebuild each channel's in-memory owner map from persisted `armedAlarms` for every
    /// non-terminal Badger, so `observe()` can attribute firings of alarms armed in a prior
    /// process after a relaunch (M3 cold-kill fix). Call at startup BEFORE `startObserving()`.
    /// Notification channels no-op (they own no live map).
    public func rehydrateArmedAlarms() async {
        let all = (try? context.fetch(FetchDescriptor<Badger>())) ?? []
        for badger in all where !isTerminal(badger.state) && !badger.armedAlarms.isEmpty {
            for channel in registry.allChannels {
                await channel.adopt(badgerID: badger.id, refs: badger.armedAlarms)
            }
        }
    }

    public func startObserving() {
        for channel in registry.allChannels {
            guard let stream = channel.observe() else { continue }
            let task = Task { [weak self] in
                for await event in stream { await self?.handleChannelEvent(event) }
            }
            observationTasks.append(task)
        }
    }

    /// Map a channel's observed transition to a reducer event (observed source): a
    /// fired alarm advances the level; a bare removal is a NON-resolving dismissal
    /// (§8/§14 — only an explicit Done resolves). Internal for deterministic testing.
    func handleChannelEvent(_ event: ChannelEvent) async {
        switch event {
        case .levelFired(let badgerID, let rung):
            await dispatch(.levelFired(level: rung, source: .observed), toBadgerID: badgerID)
        case .repeatFired(let badgerID, _, let n):
            await dispatch(.lastRungRepeated(index: n, source: .observed), toBadgerID: badgerID)
        case .dismissed(let badgerID, let rung):
            await markAlarmDismissed(badgerID, rung: rung)
        }
    }

    // MARK: - Dispatch (reduce -> apply -> execute -> save)

    private func dispatch(_ event: Event, toBadgerID id: UUID) async {
        guard let badger = fetch(id) else { return }
        await dispatch(event, to: badger)
    }

    private func dispatch(_ event: Event, to badger: Badger) async {
        let ctx = makeContext(for: badger)
        let (newState, effects) = reduce(MachineState(from: badger), event, ctx)
        apply(newState, to: badger)
        stampResolved(newState, on: badger, at: ctx.now)
        await execute(effects, for: badger, state: newState, context: ctx)
        try? context.save()
    }

    private func runReconcile(on badger: Badger) async {
        let ctx = makeContext(for: badger)
        let (newState, effects) = BadgerKit.reconcile(MachineState(from: badger), ctx)
        apply(newState, to: badger)
        stampResolved(newState, on: badger, at: ctx.now)
        await execute(effects, for: badger, state: newState, context: ctx)
        try? context.save()
    }

    // MARK: - Effect execution

    private func execute(_ effects: [Effect], for badger: Badger,
                         state: MachineState, context ctx: Context) async {
        var seq = nextSequence(for: badger.id)
        for effect in effects {
            switch effect {
            case .append(let logged):
                context.insert(makeEventRecord(from: logged, badgerID: badger.id,
                                               sequence: seq, timestamp: ctx.now))
                seq += 1
            case .armSchedule(let fromLevel):
                await armSchedule(from: fromLevel, badger: badger, state: state, ctx: ctx)
            case .cancelAllPending:
                await cancelPending(for: badger)   // reads armedAlarms; cancels by id + namespace
                badger.armedAlarms = []            // clear only after teardown returns
            case .armWake(let date):
                await armWake(at: date, badger: badger)
            case .startLiveActivity(let phase, let nextFire):
                await liveActivity.start(badgerID: badger.id, title: badger.title,
                                         phase: phase, nextFire: nextFire)
            case .updateLiveActivity(let phase, let level, let nextFire):
                await liveActivity.update(badgerID: badger.id, phase: phase,
                                          level: level, nextFire: nextFire)
            case .endLiveActivity:
                await liveActivity.end(badgerID: badger.id)
            }
        }
    }

    /// Arm every rung >= fromLevel plus the bounded last-rung repeat batch, off the
    /// reduced state's (possibly re-anchored) startAt.
    private func armSchedule(from fromLevel: Int, badger: Badger,
                             state: MachineState, ctx: Context) async {
        guard let specs = badger.ladder?.rungs.sorted(by: { $0.index < $1.index }),
              !specs.isEmpty else { return }
        let last = specs.count - 1
        let rungs = ctx.rungs

        for k in fromLevel...last {
            let fire = fireDate(level: k, startAt: state.startAt, rungs: rungs)
            for action in specs[k].actions {
                if let ref = await schedule(resolve(action, for: badger), at: fire,
                                            badgerID: badger.id, slot: .rung(k)) {
                    if ref.channelID == "alarmkit" {
                        badger.armedAlarms.append(ArmedRef(id: ref.identifier, slot: .rung(k)))
                    }
                    // Notification rungs aren't persisted; NotificationChannel.cancelAll
                    // prefix-scans the system by the badger-{id}- namespace (survives cold kill).
                }
            }
        }

        let interval = repeatInterval(rungs: rungs)
        if interval > 0 {
            let firstLastFire = fireDate(level: last, startAt: state.startAt, rungs: rungs)
            for n in 1...repeatBatchSize {
                let fire = firstLastFire.addingTimeInterval(Double(n) * interval)
                for action in specs[last].actions {
                    if let ref = await schedule(resolve(action, for: badger), at: fire,
                                                badgerID: badger.id, slot: .repeatTail(rung: last, n: n)),
                       ref.channelID == "alarmkit" {
                        badger.armedAlarms.append(ArmedRef(id: ref.identifier, slot: .repeatTail(rung: last, n: n)))
                    }
                }
            }
        }
    }

    /// A time-sensitive nudge at the snooze resume time. The actual SnoozeExpired
    /// transition is driven by reconcile on foreground/tap (§14), not by this firing.
    private func armWake(at date: Date, badger: Badger) async {
        let action = ChannelAction(channelID: "notification", prominence: .timeSensitive,
                                   message: badger.title)
        _ = await schedule(action, at: date, badgerID: badger.id, slot: .wake)
    }

    private func schedule(_ action: ChannelAction, at fire: Date,
                          badgerID: UUID, slot: ScheduleSlot) async -> ScheduledRef? {
        guard let channel = registry.channel(for: action.channelID) else {
            log("no channel registered for id '\(action.channelID)' — skipping \(slot)")
            return nil
        }
        do {
            return try await channel.schedule(action, at: fire, recurrence: nil,
                                              badgerID: badgerID, slot: slot)
        } catch {
            log("schedule failed on '\(action.channelID)' \(slot): \(error)")
            return nil
        }
    }

    /// Tear down a Badger's alerts durably: cancel persisted AlarmKit alarms by id
    /// (cold-kill-safe — no owners-map dependency) and prefix-scan notifications by
    /// namespace. Callers clear `badger.armedAlarms` only after this returns.
    private func cancelPending(for badger: Badger) async {
        let armedIDs = badger.armedAlarms.map(\.id)
        for channel in registry.allChannels {
            await channel.cancel(identifiers: armedIDs)       // durable id teardown (AlarmKit)
            await channel.cancelAll(forBadgerID: badger.id)   // namespace teardown (notifications)
        }
    }

    // MARK: - Helpers

    /// §6: a rung's alert text defaults to the Badger title.
    private func resolve(_ action: ChannelAction, for badger: Badger) -> ChannelAction {
        var a = action
        if a.message == nil { a.message = badger.title }
        return a
    }

    private func makeContext(for badger: Badger) -> Context {
        let rungs = (badger.ladder?.rungs ?? [])
            .sorted { $0.index < $1.index }
            .map { Rung(index: $0.index, delay: $0.delay) }
        return Context(now: now(), rungs: rungs, maxSnoozeCount: badger.maxSnoozeCount)
    }

    private func stampResolved(_ state: MachineState, on badger: Badger, at when: Date) {
        if state.status.isTerminal, badger.resolvedAt == nil { badger.resolvedAt = when }
    }

    private func isTerminal(_ s: StoredBadgerState) -> Bool { s == .done || s == .stopped }

    private func fetch(_ id: UUID) -> Badger? {
        var fd = FetchDescriptor<Badger>(predicate: #Predicate { $0.id == id })
        fd.fetchLimit = 1
        return (try? context.fetch(fd))?.first
    }

    /// All Badgers newest-first (createdAt desc). Read side for the M4 snapshots.
    private func fetchAll() -> [Badger] {
        var fd = FetchDescriptor<Badger>()
        fd.sortBy = [SortDescriptor(\.createdAt, order: .reverse)]
        return (try? context.fetch(fd)) ?? []
    }

    /// Project a Badger to its Sendable read model (main-actor read of the @Model).
    private func snapshot(of badger: Badger) -> BadgerSnapshot {
        BadgerSnapshot(id: badger.id, title: badger.title, notes: badger.notes,
                       state: badger.state, currentLevel: badger.currentLevel,
                       totalLevels: badger.ladder?.rungs.count ?? 0,
                       iconName: badger.iconName, tint: badger.tint)
    }

    private func nextSequence(for badgerID: UUID) -> Int {
        var fd = FetchDescriptor<EventRecord>(predicate: #Predicate { $0.badgerID == badgerID })
        fd.sortBy = [SortDescriptor(\.sequence, order: .reverse)]
        fd.fetchLimit = 1
        return ((try? context.fetch(fd))?.first?.sequence ?? -1) + 1
    }

    private func log(_ message: String) { print("[BadgerEngine] \(message)") }
}
