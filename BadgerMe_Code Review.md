

# BadgerMe — Code Review (M1–M3)
 
**Date:** 2026-07-07
**Repo:** `/Users/amosglenn/Dev/BadgerMe`
**HEAD reviewed:** `a37b893` — *feat: M3 — AlarmKit channel (breakthrough rungs, observe, resolve-from-alarm)*
**Scope:** the `BadgerKit` package (domain + engine + channels), the app target (`BadgerMe`), the widget target (`BadgerMeWidget`), the four test suites, and the `Notes/` docs (spec, checklist, `NEXT-SESSION.md`).
 
## Verification baseline (as reviewed)
 
- `swift test` in `BadgerKit/`: **41 tests / 4 suites, all green** (matches `NEXT-SESSION.md`; the older "38 tests" baseline was pre-M3).
- `xcodebuild … -destination 'generic/platform=iOS Simulator' build`: **BUILD SUCCEEDED, zero warnings.** This confirms the iOS-only M3 code compiles — `AlarmKitChannel`, `MarkBadgerDoneIntent`, the unguarded `@available(iOS 26.1, *)` instantiation, and the omitted `stopIntent` all build clean. (`swift test` on macOS skips these files because they are behind `#if canImport(AlarmKit)` / `#if os(iOS)`.)
- Working tree clean.
## Decision coherence — verified consistent
 
The two decisions most at risk of drifting from the code are both fully reconciled on disk and match the implementation:
 
| Decision | Status | Verified against code |
|---|---|---|
| **D4 / SP3** — no arbitrary-interval AlarmKit recurrence; last-rung repeat is batch-and-replenish for *both* channels | Reconciled in §8, §10, §14, §9 table, D4, D12, §20 with dated notes | Every channel declares `supportsArbitraryRecurrence: false`; `schedule` always passes `recurrence: nil`; engine arms a `repeatBatchSize` batch. **No conflict.** |
| **D9** — 26.1 deployment floor | Reconciled in §4 and D9 with dated rationale | App/test targets are `IPHONEOS_DEPLOYMENT_TARGET = 26.1`; `AlarmKitChannel` (`@available(iOS 26.1, *)`) is instantiated unguarded, which only compiles at a 26.1 floor. **Consistent.** |
 
`snoozeUntil` (§6, "Added in M1") also matches the `Badger` model. **Note:** the `/mnt/project` mounted spec copy is stale on all of the above — the on-disk `Notes/BadgerMe-Build-Specification.md` is the correct one.
 
## Issue summary
 
| # | Issue | Category | Severity |
|---|---|---|---|
| 1 | "No-op migration stage" described in docs but not implementable/implemented | Doc↔code | Medium |
| 2 | `stopIntent` specified in §8 but omitted in `AlarmKitChannel` | Doc↔code | Medium |
| 3 | `ChannelEvent` can't express a repeat-tail fire; owners map drops the slot | Design gap | Medium–High (latent, bites M5/M6) |
| 4 | AlarmKit snapshot-diffing (`diff`) has zero automated coverage | Testability | Medium |
| 5 | `armedAlarmIDs` / `armedNotificationIDs` are write-only | Simplification | Low |
| 6 | `NotificationChannel.cancelAll` can leave delivered notifications in the tray | Correctness (minor) | Low |
| 7 | Widget target is Swift 5.0 / iOS 26.5 while app is 6.0 / 26.1 | Build hygiene | Medium (before M5) |
| 8 | Cosmetic staleness (dev-harness "(M2)" label, no breakthrough dev ladder, "32 tests" note) | Cosmetic | Low |
| 9 | `apply(_:to:)` leaves stale `currentLevel` on `.pending` | Forward-looking | Low (activates at M4 Replace/Edit) |
 
---
 
## 1. The "no-op migration stage" is described but does not exist
 
**Where:** spec §6, §18, §21-M0; `PersistenceTests.swift` (`containerOpens` and file header); `Schema.swift`.
 
**Problem.** The spec repeatedly describes "a trivial no-op lightweight stage so the plan is exercised before any real stage," and the tests claim to be "exercising the migration plan's no-op path." But `BadgerMigrationPlan.stages` is `[]`, and a `MigrationStage` is inexpressible with a single schema version — a stage requires both a `fromVersion` and a `toVersion`. So the code is *correct* (there is nothing to migrate yet) and the documentation overstates: nothing runs a stage. `containerOpens` merely opens the container against the single-version schema.
 
**Impact.** Purely documentation accuracy; no runtime effect. But it can mislead a future reader into thinking migration is being exercised when it isn't.
 
**Suggested edits (docs + test comment).**
 
- §6 (Schema versioning, L13): replace "include a trivial no-op lightweight stage so the plan is exercised before any real stage" with wording like:
  > Wire in `BadgerMigrationPlan: SchemaMigrationPlan` with `stages: []` from day one. A `MigrationStage` cannot be expressed against a single schema version, so V1 has no stage — the first stage is authored alongside V2 (the first persistent field addition), at which point it becomes a tested migration rather than a data-loss emergency.
- §18 (Schema/migration test): change "the no-op stage runs" to "the container opens against `BadgerSchemaV1` with the (empty) migration plan attached; existing Codable round-trips are unaffected. The first real stage is tested when V2 is added."
- `PersistenceTests.swift`: change the header line and the `containerOpens` test name/comment from "exercising the migration plan's no-op path" / "no-op migration plan" to "opens against the single-version schema with the (empty) migration plan attached."
---
 
## 2. `stopIntent` is specified in §8 but omitted in `AlarmKitChannel`
 
**Where:** spec §8 (lines ~261, ~263, ~582e) vs. `AlarmKitChannel.schedule`.
 
**Problem.** §8 says hard-rung alarms carry *both* a `stopIntent` and a `secondaryIntent` on the `AlarmConfiguration`. The code sets only `secondaryIntent`:
 
```swift
let config = AlarmManager.AlarmConfiguration(
    schedule: .fixed(fireDate),
    attributes: attributes,
    secondaryIntent: MarkBadgerDoneIntent(badgerID: badgerID.uuidString),
    sound: sound(for: action.soundRef))
```
 
It compiles (`stopIntent` defaults to `nil`) and is arguably fine — a Stop is a bare removal, which the `alarmUpdates` snapshot diff detects as a disappearance and reports as `.dismissed` (non-resolving, §8).
 
**Impact.** Real but bounded. `observe()` only runs while the app is alive, and `reconcile` infers fires / last-rung repeats / snooze-expiry but **not** dismissals. So a **Stop performed while the app is backgrounded is never logged as `alarmDismissed`** — the event log silently loses it. Correctness is unaffected (dismissal doesn't resolve; the ladder continues), but the history/audit record is incomplete.
 
**Suggested resolution (pick one).**
 
- **Add the `stopIntent`** (matches §8): supply a lightweight `LiveActivityIntent` that logs `alarmDismissed` for the Badger, so the system can background-launch the app to run it on Stop. (Whether it runs headless when force-quit is SP4-adjacent and still device-pending — verify.)
- **Or update §8** to state that stop is intentionally observed-only via the disappearance in `alarmUpdates`, that `stopIntent` is deliberately omitted, and that dismissal logging is therefore best-effort / live-only. Given the diff already covers the live case and correctness doesn't depend on the log entry, this is the lower-effort, honest option — but document the backgrounded-Stop-not-logged consequence explicitly.
---
 
## 3. `ChannelEvent` cannot represent a repeat-tail fire; the owners map discards the slot
 
**Where:** `AlertChannel.swift` (`ChannelEvent`), `AlarmKitChannel.swift` (`owners`, `diff`, `rungIndex`), `BadgerEngine.handleChannelEvent`.
 
**Problem.** `AlarmKitChannel.owners` stores only `[alarmID: (badgerID, rung)]`, and `ChannelEvent` has only `.levelFired` and `.dismissed`. When a `.repeatTail(rung: last, n:)` alarm fires while the app is running, `diff` emits `.levelFired(rung: last)` (via `rungIndex`, which collapses `repeatTail` to its base rung). The engine maps that to `.levelFired(level: last, source: .observed)`, and the reducer no-ops it because the Badger is already `active(last)` (`guard level > k` fails).
 
Net effect on the **live path:** last-rung repeats produce **no `lastRungRepeated` log entry and no Live-Activity refresh**. Only `reconcile` records repeats (via inferred `lastRungRepeated` events). The engine test comment already acknowledges the seam: *"base rungs 0 and 1 (repeat tail is not stored)."*
 
**Impact.** Tolerable in M3 (no Live Activity yet; the repeat batch/replenish is M6). But it is a latent gap that will surface in **M5** (ambient LA won't advance to the next repeat live) and **M6** (repeat telemetry/replenish triggers). The channel has also *lost* the repeat index `n` by diff time, since `owners` drops it.
 
**Suggested edit.**
 
- Widen the event vocabulary and store the full slot:
```swift
public enum ChannelEvent: Sendable, Equatable {
    case levelFired(badgerID: UUID, rung: Int)
    case repeatFired(badgerID: UUID, rung: Int, n: Int)   // NEW
    case dismissed(badgerID: UUID, rung: Int)
}
 
// AlarmKitChannel: store the slot, not just the rung
private var owners: [UUID: (badgerID: UUID, slot: ScheduleSlot)] = [:]
```
 
- In `diff`, when an owned alarm enters `.alerting`, branch on `owner.slot`: `.rung(k)` → `.levelFired`; `.repeatTail(rung, n)` → `.repeatFired`.
- In `BadgerEngine.handleChannelEvent`, map `.repeatFired` to `reduce(... .lastRungRepeated(index: n, source: .observed) ...)`.
- **Alternative (lower effort):** keep the vocabulary as-is but explicitly document in `AlarmChannel.swift`/§14 that live repeat firings are intentionally silent and that `reconcile` is the sole owner of repeat accounting. This is acceptable only if M5's LA is content to rely on its fixed-target countdown + reconcile refresh for the repeating phase.
---
 
## 4. AlarmKit snapshot-diffing has zero automated coverage
 
**Where:** `AlarmKitChannel.diff(_:)`.
 
**Problem.** `diff` is the most novel and error-prone piece of M3: it diffs an app-global snapshot against last-known per-alarm state, detects `.alerting` transitions and disappearances, and mutates the owners/`lastStates` bookkeeping. But it is `private`, actor-isolated, and typed against `[Alarm]`, so `swift test` on macOS skips the whole file, and the engine tests exercise a `FakeAlarmChannel` instead. The real diffing logic is currently only validated by on-device spikes (SP2/4/5/6).
 
**Impact.** The trickiest logic in the milestone is untested. Regressions in the diff (e.g., a missed disappearance, a double-fire) would only surface on device.
 
**Suggested edit.** Extract the pure diff into a free function over a tiny local value type (not `[Alarm]`), so it is unit-testable without AlarmKit:
 
```swift
// Testable, AlarmKit-free:
struct AlarmSnapshotEntry: Equatable { let id: UUID; let isAlerting: Bool }
 
func diffAlarmSnapshot(
    entries: [AlarmSnapshotEntry],
    owners: [UUID: (badgerID: UUID, slot: ScheduleSlot)],
    lastAlerting: [UUID: Bool]
) -> (events: [ChannelEvent],
      newLastAlerting: [UUID: Bool],
      removedOwners: [UUID]) { … }
```
 
Then `AlarmKitChannel.diff` becomes a thin adapter that maps `[Alarm]` → `[AlarmSnapshotEntry]` and applies the result. Add a suite covering: first fire, duplicate snapshot (no re-fire), disappearance = dismissal, unowned alarm ignored, repeat-tail fire (ties to Issue 3).
 
---
 
## 5. `armedAlarmIDs` / `armedNotificationIDs` are write-only
 
**Where:** `BadgerEngine.armSchedule` (writes), `cancelAllPending` handling (clears), `PersistenceModels.Badger` (fields); spec §6.
 
**Problem.** These maps are populated on every arm and cleared on cancel, but **nothing ever reads them**. Teardown goes through `channel.cancelAll(forBadgerID:)` — prefix-scan for notifications, the in-memory owners map for AlarmKit — which the spec now concedes (§9 / line ~308 / ~582i: *"metadata-based cancellation is infeasible as once imagined"*). §6 still frames these maps as the direct cancellation mechanism (replacing P1's SHA reverse-lookup), so the field's stated purpose no longer matches how cancellation actually works.
 
**Impact.** Harmless but vestigial: extra writes and persisted state that no code consumes. (`liveActivityID` and `focusTags` are also currently unused, but those are legitimately forward-declared for M5 / M6-§13 and should stay.)
 
**Suggested resolution (pick one).**
 
- Wire the maps to a real **targeted per-slot cancel** (e.g., a future "cancel just rung k" path), which would give them a reader.
- Or relabel them in §6 as reserved / diagnostic (recording what's armed for the history UI) rather than the cancellation index.
- Or drop the writes until a reader exists.
---
 
## 6. `NotificationChannel.cancelAll` can leave delivered notifications in the tray
 
**Where:** `NotificationChannel.cancelAll(forBadgerID:)`.
 
**Problem.** It derives `ids` from `pendingNotificationRequests()` only, then calls both `removePendingNotificationRequests` and `removeDeliveredNotifications` on that same pending-derived set:
 
```swift
let pending = await center.pendingNotificationRequests()
let ids = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
center.removePendingNotificationRequests(withIdentifiers: ids)
center.removeDeliveredNotifications(withIdentifiers: ids)   // ids are PENDING ids only
```
 
A notification that has already fired is *delivered, not pending*, so its id isn't in `ids` and won't be cleared from Notification Center.
 
**Impact.** For a nag app where Done should wipe the slate, stale delivered banners can linger after `cancelAll`. Minor UX wart, not a correctness break.
 
**Suggested edit.** Scan delivered notifications as well:
 
```swift
public func cancelAll(forBadgerID badgerID: UUID) async {
    let prefix = BadgerNotifications.identifierPrefix(badgerID: badgerID)
    let pending = await center.pendingNotificationRequests()
        .map(\.identifier).filter { $0.hasPrefix(prefix) }
    let delivered = await center.deliveredNotifications()
        .map(\.request.identifier).filter { $0.hasPrefix(prefix) }
    center.removePendingNotificationRequests(withIdentifiers: pending)
    center.removeDeliveredNotifications(withIdentifiers: delivered)
}
```
 
---
 
## 7. Widget target is Swift 5.0 / iOS 26.5 while the app is 6.0 / 26.1
 
**Where:** `BadgerMe.xcodeproj/project.pbxproj` — `BadgerMeWidget` build configs.
 
**Problem.** App, test, and package targets are `SWIFT_VERSION = 6.0` / `IPHONEOS_DEPLOYMENT_TARGET = 26.1`. The `BadgerMeWidget` extension is `SWIFT_VERSION = 5.0` / `IPHONEOS_DEPLOYMENT_TARGET = 26.5` (both look like leftover Xcode template defaults, where 26.5 = the build SDK version). `NEXT-SESSION.md` flags the **26.5 floor** (the widget/Live Activity wouldn't load on a 26.1–26.4 device) but does **not** mention the **Swift 5.0** language mode.
 
**Impact.** Two issues: (a) a widget min-OS higher than its host app is backwards — on 26.1–26.4 the extension is unavailable; (b) before M5 puts real, concurrency-sensitive, BadgerKit-consuming code in the widget, a Swift 5 module against a Swift 6 package is an inconsistent and surprising concurrency model.
 
**Suggested edit.** Set the widget's `SWIFT_VERSION = 6.0` and `IPHONEOS_DEPLOYMENT_TARGET = 26.1` (unless a genuinely 26.5-only API is needed there). These are plain build-setting *value* edits — they fit the surgical guarded-Python pbxproj approach (with `plutil -lint` after), not a GUI structural change. Do this before M5.
 
---
 
## 8. Cosmetic staleness
 
**Where:** `ContentView.swift`; spec line ~211.
 
- `ContentView`'s dev-harness section header reads **"Dev harness (M2)"** — now M3.
- The dev `devLadder` is **notification-only**; there is no breakthrough (alarmkit) ladder button to exercise the M3 alarm path on device, which SP2/SP4/SP5 require. Consider adding a second DEBUG button that creates an `alarmkit` / `.breakthrough` ladder.
- The spec's **M1 implementation note (line ~211)** still cites "32 tests." It's explicitly dated, so it reads as historical — optionally add a parallel M3 note with the current 41 count.
**Impact.** Cosmetic only.
 
---
 
## 9. `apply(_:to:)` leaves a stale `currentLevel` on `.pending` (forward-looking)
 
**Where:** `Projection.swift` `apply(_:to:)`.
 
**Problem.** The `.pending` (and terminal) branches deliberately do not write `currentLevel`. Harmless today: `pending` only occurs at `create`, where the `Badger` initializes `currentLevel = 0`, and `MachineState(from:)` ignores the level for pending. But once **M4** wires `Replace` / `Edit`, a Badger returning to `pending` from a terminal/active state will keep its old `currentLevel` in the cache — invisible to state reconstruction, but misleading to any UI reading `badger.currentLevel` directly. `ProjectionTests.roundTrip` already works around this by manually copying `currentLevel` before `apply`.
 
**Impact.** None yet; activates when Replace/Edit lands.
 
**Suggested edit.** Reset `currentLevel` to 0 in the `.pending` branch of `apply` when Replace is wired:
 
```swift
case .pending:
    badger.state = .pending
    badger.currentLevel = 0      // add when Replace/Edit can return to pending
    badger.snoozeUntil = nil
```
 
---
 
## Recommended order
 
1. **#7 (widget target settings)** — quick pbxproj value edit; do before any M5 widget code.
2. **#3 (repeat-event gap)** and **#4 (testable diff)** — highest-leverage code changes before M5/M6; #4 pairs naturally with adding the repeat-tail test in #3.
3. **#1, #2, #5 (doc/spec reconciliation)** — fold into the spec's dated as-built notes.
4. **#6, #8, #9** — low-priority polish; #9 rides along with the M4 Replace/Edit work.
## Overall
 
The domain core is clean and well-covered, the reducer / engine / channel separation holds, the pure reducer stays Foundation-only with the impure engine as the sole I/O boundary, and the spike-driven spec reconciliation (D4/SP3, D9, the AlarmKit SDK facts) is genuinely well-maintained. Nothing here is blocking M4. The items with the most leverage are #3, #4, and #7.
 
