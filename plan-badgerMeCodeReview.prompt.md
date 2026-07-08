# BadgerMe update plan from `BadgerMe_Code Review.md`

## Scope and decisions (confirmed)
- Scope: implement **all 9 review items** in phased order.
- Issue #2: **implement `stopIntent`** (not docs-only).
- Issue #3: **implement full event-model change now** (`repeatFired` + full `ScheduleSlot` ownership).
- Issue #5: consult spec, then prefer **keep fields and relabel as reserved/diagnostic** if no conflict; include explicit note referencing **Issue 5 in `BadgerMe_Code Review.md`** wherever this change is made.
- Issue #9: implement now as safe forward-compatible fix.
- Delivery shape: **multiple small PRs by phase**.
- Device checks: treat SP2/SP4/SP9/SP13 as **blocking gates where behavior depends on them**.

---

## Phase 0 — baseline and guardrails (prep, no behavior changes)
1. Confirm clean baseline:
   - `git --no-pager status`
   - `(cd BadgerKit && swift test)`
   - `xcodebuild -project BadgerMe.xcodeproj -scheme BadgerMe -configuration Debug -destination 'generic/platform=iOS Simulator' build`
2. Snapshot current behavior assumptions in PR descriptions:
   - AlarmKit diff is currently untested.
   - Widget target mismatch exists (26.5 / Swift 5.0).
3. Do not bundle feature changes in this prep PR.

Acceptance:
- Baseline test/build output attached to first implementation PR.

---

## PR 1 — Build hygiene + low-risk correctness
Targets:
- Issue #7 (widget target settings)
- Issue #6 (notification delivered-tray cleanup)
- Issue #8 (cosmetic staleness)
- Issue #9 (pending state level reset now)

Files:
- `BadgerMe.xcodeproj/project.pbxproj`
  - `BadgerMeWidget` Debug/Release: set
    - `IPHONEOS_DEPLOYMENT_TARGET = 26.1`
    - `SWIFT_VERSION = 6.0`
  - Run `plutil -lint BadgerMe.xcodeproj/project.pbxproj`.
- `BadgerKit/Sources/BadgerKit/NotificationChannel.swift`
  - Update `cancelAll` to separately scan `pendingNotificationRequests()` and `deliveredNotifications()`.
- `BadgerMe/ContentView.swift`
  - Rename dev section label to M3+ wording.
  - Add DEBUG breakthrough ladder button for AlarmKit dev-path exercise.
- `BadgerKit/Sources/BadgerKit/Projection.swift`
  - In `.pending`, set `badger.currentLevel = 0`.
- Optional associated tests:
  - `BadgerKit/Tests/BadgerKitTests/ProjectionTests.swift` add/adjust coverage for pending reset.

Verification:
- `(cd BadgerKit && swift test)`
- `xcodebuild ... build`
- `plutil -lint` on pbxproj.

---

## PR 2 — Repeat-tail event model fix (core behavior)
Targets:
- Issue #3 (full fix now)

Files:
- `BadgerKit/Sources/BadgerKit/AlertChannel.swift`
  - Extend `ChannelEvent` with:
    - `case repeatFired(badgerID: UUID, rung: Int, n: Int)`
- `BadgerKit/Sources/BadgerKit/AlarmKitChannel.swift`
  - Change `owners` to store full slot:
    - `[UUID: (badgerID: UUID, slot: ScheduleSlot)]`
  - On alerting transition:
    - `.rung(k)` -> `.levelFired(...)`
    - `.repeatTail(rung, n)` -> `.repeatFired(...)`
  - Keep dismissal mapping consistent.
- `BadgerKit/Sources/BadgerKit/BadgerEngine.swift`
  - Map `.repeatFired` to reducer event:
    - `.lastRungRepeated(index: n, source: .observed)`
- `BadgerKit/Tests/BadgerKitTests/EngineTests.swift`
  - Add tests that observed repeat-tail fires produce `lastRungRepeated` logging/state behavior.
  - Update any assertions that assumed repeat tails are not represented.

Verification:
- `(cd BadgerKit && swift test)`
- `xcodebuild ... build`

---

## PR 3 — AlarmKit snapshot diff extraction + testability
Targets:
- Issue #4

Implementation shape:
- Extract pure diff logic from `AlarmKitChannel.diff(_:)` into AlarmKit-free unit-testable logic.
- Suggested value type:
  - `AlarmSnapshotEntry { id: UUID, isAlerting: Bool }`
- Suggested pure function input/output:
  - input: snapshot entries, owners map, last-alerting map
  - output: events, new last-alerting map, removed owners IDs
- Keep `AlarmKitChannel` as thin adapter over `Alarm` snapshots.

Files:
- `BadgerKit/Sources/BadgerKit/AlarmKitChannel.swift` (adapter)
- New/adjacent pure helper file in `BadgerKit/Sources/BadgerKit/`
- New tests in `BadgerKit/Tests/BadgerKitTests/` covering:
  - first alerting transition emits once
  - repeated snapshot doesn’t double-fire
  - disappearance emits dismissal and cleanup
  - unowned alarms ignored
  - repeat-tail emits `repeatFired` (ties to PR 2)

Verification:
- `(cd BadgerKit && swift test)` (must include new diff tests)
- `xcodebuild ... build`

---

## PR 4 — Alarm stop intent behavior + dismissal logging robustness
Targets:
- Issue #2

Files:
- `BadgerKit/Sources/BadgerKit/AlarmKitChannel.swift`
  - Provide `stopIntent` in `AlarmConfiguration` alongside `secondaryIntent`.
- Add new intent file in `BadgerKit/Sources/BadgerKit/`:
  - e.g., `MarkBadgerDismissedIntent.swift` (`LiveActivityIntent`)
  - parameterized by badgerID + rung (or equivalent needed to log dismissal deterministically)
  - resolves engine via `@Dependency`.
- `BadgerKit/Sources/BadgerKit/BadgerEngine.swift`
  - add explicit API used by stop intent to append/log dismissal without resolving.
- If needed, update `BadgerMe/AppDelegate.swift` DI registration comments/docs.

Tests:
- Add intent/engine-path tests where feasible in package tests.
- Ensure no path resolves the Badger on stop; only logs dismissal.

Blocking device gates (must be run before merge if behavior depends on them):
- SP4: verify stop/secondary intent behavior with app force-quit.
- SP2/SP9/SP13 as applicable to changed alarm behavior expectations.

Verification:
- `(cd BadgerKit && swift test)`
- `xcodebuild ... build`
- Document device-check outcomes in `Notes/BadgerMe-Capability-Spike-Checklist.md` and reconcile spec notes.

---

## PR 5 — Documentation and terminology reconciliation
Targets:
- Issue #1, #5, and remaining #8 spec-note cleanup

Files:
- `Notes/BadgerMe-Build-Specification.md`
  - Fix no-op migration wording:
    - clarify `stages: []` for V1, first real stage lands with V2.
  - Align AlarmKit `stopIntent` text to implemented behavior.
  - Reconcile `armedAlarmIDs` / `armedNotificationIDs` purpose with as-built cancellation mechanism:
    - keep fields, relabel as reserved/diagnostic unless an active reader is introduced.
    - add explicit note referencing **Issue 5 in `BadgerMe_Code Review.md`** at each adjusted rationale section.
  - Update outdated test-count/history notes as dated as-built entries.
- `BadgerKit/Tests/BadgerKitTests/PersistenceTests.swift`
  - Rename comment/test text from “no-op migration stage path” to “single-version schema with empty plan attached.”
- Any other directly linked notes (`Notes/NEXT-SESSION.md`) if milestone handoff text must reflect completed fixes.

Verification:
- Docs consistency read-through against current code.
- If any code touched in this PR: run `(cd BadgerKit && swift test)` and `xcodebuild ... build`.

---

## Cross-PR constraints for the implementing agent
- Keep PRs surgical and independent; avoid mixing unrelated issues.
- Re-run package tests and app build on every PR.
- Preserve existing behavior unless explicitly changed by review item.
- For AlarmKit/iOS-only code, keep macOS `swift test` compatibility via existing compile guards.
- Any intentional divergence from spec text must include dated rationale.

## Suggested PR order
1. PR 1 (hygiene + low-risk correctness)
2. PR 2 (repeat event-model fix)
3. PR 3 (diff extraction + tests)
4. PR 4 (stop intent)
5. PR 5 (docs reconciliation, including Issue 5 note)
