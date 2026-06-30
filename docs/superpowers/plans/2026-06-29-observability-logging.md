# Observability — Durable Diagnostic Log + Better Viewer — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Spec: `docs/superpowers/specs/2026-06-29-observability-logging-design.md`.

**Goal:** Make every background task and both outboxes observable — durably, across app relaunches — and give About → Logs a real viewer, so the user can see what happened to an offline vote and which instance is failing `getSite`.

**Architecture:** A single append-only GRDB table `diagnosticEvent` (migration `v26`) records curated lifecycle events. A `Sendable` `DiagnosticLog` recorder fans each event to OSLog *and* the table. Writers (both outboxes, scheduler, getSite, unread, offline download, lifecycle, spotlight) emit events at their boundaries. The About → Logs screen becomes a two-tab SwiftUI viewer: a durable Event Log (filter/search/detail/share/clear) and a fixed OSLog System Log tail.

**Tech Stack:** Swift 6 (language mode 6.0 on shipped targets), UIKit + SwiftUI (About screen is SwiftUI), GRDB, LemmyKit (remote SPM pin 0.5.0), Swift Testing (SpudDataKitTests), pointfreeco/swift-snapshot-testing (SpudSnapshots), XcodeGen.

## Global Constraints

- **Swift strict concurrency** `SWIFT_STRICT_CONCURRENCY = complete`; new SpudDataKit/Spud code is Swift 6.0 language mode. Records are `Sendable` structs; the recorder is `Sendable`.
- **No emojis** in code, comments, docs, or commit messages. Conventional commit subjects (`feat:`/`fix:`/`refactor:`/`test:`/`docs:`).
- **Branch:** all work on `feat/logging-observability` (worktree `.claude/worktrees/logging-observability`, spec committed first). Verify `git branch --show-current` before every commit. Never `git add -A`; stage explicit paths. Never touch `.remember/remember.md` or anything under another `/worktrees/` path.
- **After adding/removing source files,** run `make project` (XcodeGen) before building, or Xcode won't see them.
- **Build/test:** app builds via `python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud`. SpudDataKit unit tests: `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud -only-testing:SpudDataKitTests -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation -skipMacroValidation test`. Snapshots: `-testPlan SpudSnapshots -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.3.1'`.
- **GRDB observations** must pass `.async(onQueue: .global(qos: .userInitiated))` (never the default main scheduler — illegal from non-isolated AsyncStream init).
- **Migrations:** append `v26_diagnosticEvent` as the next case in `AppDatabase+Migrations.swift` (head is `v25_offlineWebArchive`); never edit a shipped migration.
- **Records** use `Codable, FetchableRecord, MutablePersistableRecord, Sendable, Equatable` with property-based column inference and a `didInsert` hook (mirror `PendingOperationRecord`).
- **Privacy:** store the instance **host** (non-secret) in clear; never store the raw `accountKeychainId`, tokens, or passwords. `SwiftFormat` (`mint run swiftformat <paths>`) runs before the final verify, never after.
- **Run `mint run swiftformat`** on touched files before the final test verify of each task. Mind `--enable isEmpty` (guard `x.count == 0` rewrites with `// swiftformat:disable:next isEmpty` when the type lacks `isEmpty`).
- **Do NOT change** `OutboxFailureClass.classify`, rollback, or retry control flow. Instrumentation is additive only this iteration.

---

## File Structure

**New — SpudDataKit:**
- `Services/AppDatabase/Records/DiagnosticEventRecord.swift` — record + `DiagnosticCategory` + `DiagnosticLevel` enums.
- `Services/AppDatabase/DiagnosticEventWrites.swift` — `AppDatabase` extension: insert, recent(filter), prune, clear.
- `Services/AppDatabase/DiagnosticEventObservations.swift` — `observeDiagnosticEvents(filter:)`.
- `Services/Diagnostics/DiagnosticLog.swift` — `DiagnosticLogging` protocol, `DiagnosticLog` (dual-sink), `DiagnosticLogFilter`, `DiagnosticLogSpy` (test double, `#if DEBUG` or test-target only).

**Modified — SpudDataKit:**
- `Services/AppDatabase/AppDatabase+Migrations.swift` — add `v26_diagnosticEvent`.
- `Utils/Logger.swift` — add `outbox`, `composerOutbox`, `inbox` categories.
- `Services/Outbox/OutboxService.swift`, `Services/Outbox/ComposerOutboxService.swift` — inject `DiagnosticLogging`, emit events, accept instance host.
- `Services/Scheduler/SchedulerService.swift`, `Services/Lemmy/LemmyService.swift`, `Services/Inbox/UnreadCountService.swift`, `Services/Offline/OfflineDownloadService.swift` — emit events; getSite host.
- Dependency container (where services are constructed — `DependencyContainer`/`AppDelegate` wiring) — build one `DiagnosticLog`, inject everywhere.

**New — Spud (app):**
- `Scenes/Preferences/About/Logs/DiagnosticLogView.swift` (+ `DiagnosticLogRowView`, `DiagnosticLogDetailView`, `DiagnosticLogViewModel`).
- `Scenes/Preferences/About/Logs/SystemLogView.swift`.

**Modified — Spud (app):**
- `Scenes/Preferences/About/PreferencesAboutView.swift` — host the two-tab viewer.
- `Integration/SceneDelegate.swift`, `Scenes/MainWindow/MainWindow.swift`, `CommunitySpotlightIndexer`, `ContentSpotlightIndexer` — lifecycle/finish events.

---

## PHASE 1 — Durable store + recorder (headless)

Delivers a fully-tested data layer + recorder. No writers wired yet.

### Task 1: `DiagnosticEventRecord` + `DiagnosticCategory` + `DiagnosticLevel`

**Files:**
- Create: `SpudDataKit/Services/AppDatabase/Records/DiagnosticEventRecord.swift`
- Test: `SpudDataKitTests/DiagnosticEventRecordTests.swift`

**Interfaces produced:**
- `public enum DiagnosticCategory: String, Sendable, CaseIterable, Codable { case outbox, composerOutbox, scheduler, site, offlineDownload, unread, spotlight, lifecycle }`
- `public enum DiagnosticLevel: Int, Sendable, Codable, Comparable { case debug = 0, info = 1, notice = 2, error = 3 }` with `static func < `.
- `public struct DiagnosticEventRecord: Codable, FetchableRecord, MutablePersistableRecord, Sendable, Equatable` with `databaseTableName = "diagnosticEvent"`, fields: `var id: Int64?`, `var timestamp: Double`, `var category: String`, `var level: Int`, `var event: String`, `var message: String`, `var instance: String?`, `var metadata: String?`; `mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }`.
- Convenience: `var levelEnum: DiagnosticLevel?` and `var categoryEnum: DiagnosticCategory?` decoders; `var metadataDictionary: [String: String]?` (JSON decode).

- [ ] **Step 1: Write the failing test** — assert enum ordering (`.debug < .error`), `databaseTableName == "diagnosticEvent"`, and that `metadataDictionary` round-trips a `["httpStatus": "403"]` JSON string.
- [ ] **Step 2: `make project`, run test, verify it fails** (type not found).
- [ ] **Step 3: Implement the record** (BSD-2-Clause header like sibling records; mirror `PendingOperationRecord` structure).
- [ ] **Step 4: Run test, verify pass.**
- [ ] **Step 5: `mint run swiftformat` the two files; commit** `feat(diagnostics): add DiagnosticEventRecord + category/level enums`.

### Task 2: `v26_diagnosticEvent` migration

**Files:**
- Modify: `SpudDataKit/Services/AppDatabase/AppDatabase+Migrations.swift` (append next case)
- Test: `SpudDataKitTests/DiagnosticEventMigrationTests.swift`

**Interfaces consumed:** `DiagnosticEventRecord` (Task 1).

- [ ] **Step 1: Failing test** — `let db = try AppDatabase.inMemory(); try await db.writer.read { try $0.tableExists("diagnosticEvent") }` is `true`; the `index_diagnosticEvent_on_timestamp` index exists.
- [ ] **Step 2: Run, verify fail.**
- [ ] **Step 3: Add migration:**

```swift
migrator.registerMigration("v26_diagnosticEvent") { db in
    try db.create(table: "diagnosticEvent") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("timestamp", .double).notNull()
        t.column("category", .text).notNull()
        t.column("level", .integer).notNull()
        t.column("event", .text).notNull()
        t.column("message", .text).notNull()
        t.column("instance", .text)
        t.column("metadata", .text)
    }
    try db.create(index: "index_diagnosticEvent_on_timestamp", on: "diagnosticEvent", columns: ["timestamp"])
}
```

- [ ] **Step 4: Run, verify pass.**
- [ ] **Step 5: swiftformat; commit** `feat(diagnostics): v26_diagnosticEvent migration`.

### Task 3: `DiagnosticEventWrites` (insert / recent / prune / clear)

**Files:**
- Create: `SpudDataKit/Services/AppDatabase/DiagnosticEventWrites.swift`
- Create: `SpudDataKit/Services/Diagnostics/DiagnosticLogFilter.swift` (the filter struct, shared by writes + recorder + observations)
- Test: `SpudDataKitTests/DiagnosticEventWritesTests.swift`

**Interfaces produced:**
- `public struct DiagnosticLogFilter: Sendable, Equatable { public var categories: Set<DiagnosticCategory>?; public var minimumLevel: DiagnosticLevel; public var searchText: String?; public var limit: Int; public init(categories: Set<DiagnosticCategory>? = nil, minimumLevel: DiagnosticLevel = .debug, searchText: String? = nil, limit: Int = 1000) }`
- `extension AppDatabase`:
  - `func insertDiagnosticEvent(_ record: DiagnosticEventRecord) async throws`
  - `func recentDiagnosticEvents(_ filter: DiagnosticLogFilter) async throws -> [DiagnosticEventRecord]` — newest-first (`ORDER BY timestamp DESC, id DESC`), `level >= filter.minimumLevel.rawValue`, category IN set (when non-nil), `searchText` LIKE across message/event/instance/metadata, `LIMIT filter.limit`.
  - `func pruneDiagnosticEvents(now: Double, maxRows: Int = 10_000, maxAgeSeconds: Double = 14 * 24 * 3600) async throws` — delete `timestamp < now - maxAgeSeconds`, then delete all but the newest `maxRows` (`DELETE ... WHERE id NOT IN (SELECT id ... ORDER BY timestamp DESC LIMIT maxRows)`).
  - `func clearDiagnosticEvents() async throws`

- [ ] **Step 1: Failing tests** — insert 3 events at levels debug/notice/error; `recent(minimumLevel: .notice)` returns 2 newest-first; `recent(categories: [.outbox])` filters; `recent(searchText: "403")` matches metadata; `prune(now:, maxRows: 2)` leaves 2; `prune` drops a 15-day-old row; `clear` empties.
- [ ] **Step 2: Run, verify fail.**
- [ ] **Step 3: Implement** the extension (use `await writer.write`/`read`; note `async` overloads need `await` per CLAUDE.md). Build the search predicate from a trimmed, non-empty `searchText` only.
- [ ] **Step 4: Run, verify pass.**
- [ ] **Step 5: swiftformat; commit** `feat(diagnostics): diagnosticEvent writes + filter`.

### Task 4: `DiagnosticEventObservations`

**Files:**
- Create: `SpudDataKit/Services/AppDatabase/DiagnosticEventObservations.swift`
- Test: `SpudDataKitTests/DiagnosticEventObservationsTests.swift`

**Interfaces produced:** `extension AppDatabase { func observeDiagnosticEvents(_ filter: DiagnosticLogFilter) -> AsyncStream<[DiagnosticEventRecord]> }` — `ValueObservation` over the filtered query, started with `.async(onQueue: .global(qos: .userInitiated))`.

- [ ] **Step 1: Failing test** — start the stream, insert an event, assert the next yielded array contains it. (Use a bounded `for await ... break` with the test-timeout flags.)
- [ ] **Step 2–4:** run-fail, implement (mirror an existing `*Observations.swift`), run-pass.
- [ ] **Step 5: swiftformat; commit** `feat(diagnostics): diagnosticEvent observation`.

### Task 5: `DiagnosticLog` recorder + `DiagnosticLogging` + spy + Logger categories

**Files:**
- Create: `SpudDataKit/Services/Diagnostics/DiagnosticLog.swift`
- Modify: `SpudDataKit/Utils/Logger.swift` (add `outbox`, `composerOutbox`, `inbox` categories)
- Test: `SpudDataKitTests/DiagnosticLogTests.swift` (+ `DiagnosticLogSpy` lives in the test target, or in `DiagnosticLog.swift` under `#if DEBUG`)

**Interfaces produced:**
- `public protocol DiagnosticLogging: Sendable { func record(category: DiagnosticCategory, level: DiagnosticLevel, event: String, message: String, instance: String?, metadata: [String: String]?) async; func recent(_ filter: DiagnosticLogFilter) async -> [DiagnosticEventRecord]; func clear() async }`
- `public struct DiagnosticLog: DiagnosticLogging` wrapping `let appDatabase: AppDatabase` and a `now: @Sendable () -> Double` (default `{ Date().timeIntervalSince1970 }`, injectable for tests). `record` (a) emits to OSLog via `logger(for: category).log(level: osLogType(for: level), "...")` and (b) builds a `DiagnosticEventRecord` (JSON-encoding `metadata`) and `try? await appDatabase.insertDiagnosticEvent(...)` (best-effort; a logging failure must never crash a drain). `recent`/`clear` forward to AppDatabase.
- `osLogType(for:)` maps debug→`.debug`, info→`.info`, notice→`.default`, error→`.error`.
- `final class DiagnosticLogSpy: DiagnosticLogging, @unchecked Sendable` — records `(category, level, event, message, instance, metadata)` tuples into a lock-guarded array; `recent`/`clear` operate on it. Test helper `events(matching event: String) -> [...]`.

- [ ] **Step 1: Failing test** — `DiagnosticLog.record(category: .outbox, level: .error, event: "op.permanentRollback", message: "x", instance: "lemmy.world", metadata: ["httpStatus": "403"])` then `recent(.init(categories: [.outbox]))` returns a row whose `metadataDictionary?["httpStatus"] == "403"` and `instance == "lemmy.world"`. Separate test: `DiagnosticLogSpy` captures the call.
- [ ] **Step 2: Run, verify fail.**
- [ ] **Step 3: Implement** recorder + spy + the three Logger categories.
- [ ] **Step 4: Run, verify pass.**
- [ ] **Step 5: swiftformat; commit** `feat(diagnostics): DiagnosticLog dual-sink recorder + Logger categories`.

### Task 6: Prune-on-init wiring + build green

**Files:**
- Modify: wherever `DiagnosticLog` is first constructed at launch (the dependency container) — call `pruneDiagnosticEvents` in a detached `Task` at startup. (If the container is the right home, fold this into Phase 3 Task; otherwise a tiny standalone call.)

- [ ] **Step 1:** Build the whole app + SpudDataKit; ensure green with the new (still unused) types. `python3 .../build_and_test.py --scheme Spud`.
- [ ] **Step 2:** Run the full `SpudDataKitTests` suite; green.
- [ ] **Step 3: Commit** any wiring `chore(diagnostics): prune diagnosticEvent at launch`.

**Phase 1 acceptance:** new table + recorder fully unit-tested; app builds; nothing emits events yet.

---

## PHASE 2 — Instrument the outboxes (the vote diagnosis)

### Task 7: `OutboxService` emits lifecycle events (incl. permanent rollback)

**Files:**
- Modify: `SpudDataKit/Services/Outbox/OutboxService.swift`
- Modify: `SpudDataKit/Services/Lemmy/LemmyService.swift` (construct `OutboxService` with `diagnostics:` + `instance:` host; host via `await appDatabase.accountInstanceActorId(forKeychainId:)` → `InstanceActorId(from:)?.hostWithPort`)
- Test: `SpudDataKitTests/OutboxServiceDiagnosticsTests.swift`

**Interfaces consumed:** `DiagnosticLogging` (Task 5).
**Interfaces produced:** `OutboxService.init(..., diagnostics: DiagnosticLogging, instance: String?)`.

Emit (all `category: .outbox`, carrying `instance` and `metadata` = entityType/entityServerId/httpStatus/attempts/error as applicable):
- `enqueue` → `op.enqueue` (info)
- `drainAll`/`drainOnce` entry → `drain.start` (info; metadata `trigger`, `dueCount`)
- per record before `performer.perform` → `op.attempt` (debug; attempt#)
- success branch → `op.success` (info)
- `.transient` branch → `op.transientRetry` (notice; error, nextAttemptAt, attempt#)
- `.permanent` branch → `op.permanentRollback` (**error**; error, httpStatus if extractable) — emit **before or alongside** `emitFailure`, so the durable row exists even if no toast is shown.
- drain loop end → `drain.finish` (info; succeeded/retried/rolledBack counts)
- the nil-service skip in `LemmyService.drainPendingOutbox` (when `outboxService()` returns nil with pending rows) → `drain.skippedNoService` (**error**)

- [ ] **Step 1: Failing test** — inject a `DiagnosticLogSpy` + a fake performer that throws a `LemmyApiError.unknownServerError(403, ...)` while `isOnline == true`; enqueue a vote; drain; assert spy has exactly one `op.permanentRollback` with `metadata["httpStatus"] == "403"` and `instance` set, **and** the post's `voteStatus` was restored to baseline (existing behavior preserved).
- [ ] **Step 2: Run, verify fail** (no event emitted today).
- [ ] **Step 3: Implement** the emissions (additive; do not touch classify/rollback logic).
- [ ] **Step 4: Add tests** for transient (`op.transientRetry`) and success (`op.success`) paths; run, verify pass.
- [ ] **Step 5:** Run full `SpudDataKitTests` (guard against outbox regression); swiftformat; **commit** `feat(diagnostics): instrument OutboxService lifecycle`.

### Task 8: `ComposerOutboxService` emits lifecycle events

**Files:**
- Modify: `SpudDataKit/Services/Outbox/ComposerOutboxService.swift` (+ its construction in `LemmyService`)
- Test: `SpudDataKitTests/ComposerOutboxServiceDiagnosticsTests.swift`

Emit (`category: .composerOutbox`): `op.enqueue` (submit), `drain.start`, `op.attempt`, `op.success`, `op.transientRetry`, **`op.permanentPark`** (error; row kept), `dedup.adopt` (notice), `inflight.skip` (debug), `drain.finish`.

- [ ] **Step 1: Failing test** — spy + fake performer throwing a permanent error; submit; drain; assert one `op.permanentPark` recorded **and** the outbound row still exists with `status = failed` (existing behavior preserved). Second test: dedup adoption records `dedup.adopt`.
- [ ] **Step 2–4:** run-fail, implement, run-pass.
- [ ] **Step 5:** full suite; swiftformat; **commit** `feat(diagnostics): instrument ComposerOutboxService lifecycle`.

**Phase 2 acceptance:** an offline-vote-then-403 reproduction now leaves a durable `op.permanentRollback` row; content sends leave `op.permanentPark`. Both proven by tests.

---

## PHASE 3 — Instrument background tasks + site failures

### Task 9: getSite instance host + `site.fetchFailed`

**Files:**
- Modify: `SpudDataKit/Services/Lemmy/LemmyService.swift` (`getSiteInfo` ~line 922–932)
- Test: `SpudDataKitTests/GetSiteDiagnosticsTests.swift` (if `getSiteInfo` is unit-reachable with a fake API; otherwise assert the host-resolution helper + emit via a thin seam)

- [ ] **Step 1: Failing test** (or seam test) — a failing site fetch records `site.fetchFailed` (category `.site`, level `.error`) with `instance` = resolved host and `metadata["httpStatus"]` when available.
- [ ] **Step 2: Run, verify fail.**
- [ ] **Step 3: Implement** — resolve `let instanceHost = (await appDatabase.accountInstanceActorId(forKeychainId: accountIdentifierForLogging)).flatMap { InstanceActorId(from: $0)?.hostWithPort }`; add it to the existing `logger.error(...)` line (`instance=\(instanceHost ?? "unknown", privacy: .public)`) and emit the durable event.
- [ ] **Step 4: Run, verify pass.**
- [ ] **Step 5:** swiftformat; **commit** `feat(diagnostics): log getSite failure instance host + site.fetchFailed`.

### Task 10: SchedulerService + UnreadCountService + OfflineDownloadService

**Files:**
- Modify: `SpudDataKit/Services/Scheduler/SchedulerService.swift` — `tick.start`/`account.fetch`/`tick.finish`.
- Modify: `SpudDataKit/Services/Inbox/UnreadCountService.swift` — `refresh.start`/`refresh.finish`/`refresh.failed`; switch its `Logger.lemmyService` to `Logger.inbox`.
- Modify: `SpudDataKit/Services/Offline/OfflineDownloadService.swift` — `download.start`/`download.itemFailed`/`download.finish`|`download.cancelled` with counts.
- Test: `SpudDataKitTests/BackgroundTaskDiagnosticsTests.swift` (unit-test the unit-testable ones — UnreadCountService refresh path with a fake; Scheduler/Offline where seams allow, else assert via injected spy at the smallest reachable entry).

- [ ] **Step 1: Failing tests** for the reachable paths (e.g. `UnreadCountService.refresh` failure records `refresh.failed`).
- [ ] **Step 2–4:** run-fail, implement all three, run-pass.
- [ ] **Step 5:** full suite; swiftformat; **commit** `feat(diagnostics): instrument scheduler, unread, offline download`.

### Task 11: Lifecycle + Spotlight (app target)

**Files:**
- Modify: `Spud/Integration/SceneDelegate.swift` (`sceneWillEnterForeground` → `lifecycle.foreground`), `Spud/Scenes/MainWindow/MainWindow.swift` (`applyDefaultAccount` → `lifecycle.accountApplied` with instance; launch → `lifecycle.launch`).
- Modify: `CommunitySpotlightIndexer`/`ContentSpotlightIndexer` — `reindex.finish` (counts) + keep error logs as `reindex.failed`.
- These are app-layer; inject the shared `DiagnosticLog` from the dependency container.

- [ ] **Step 1:** Wire the shared `DiagnosticLog` into the app dependency container and the above call sites.
- [ ] **Step 2:** Build app (`build_and_test.py --scheme Spud`) green; run a quick manual smoke (launch sim, background/foreground) and confirm events appear via a temporary `recent()` dump or the Phase-4 viewer once built.
- [ ] **Step 3:** swiftformat; **commit** `feat(diagnostics): instrument lifecycle + spotlight`.

**Phase 3 acceptance:** the 403 is attributable to an instance; every background task brackets its run; orphaned-no-service is observable.

---

## PHASE 4 — The viewer (About → Logs)

### Task 12: `DiagnosticLogViewModel` + Event Log list

**Files:**
- Create: `Spud/Scenes/Preferences/About/Logs/DiagnosticLogViewModel.swift` (`@Observable`, holds `filter: DiagnosticLogFilter`, `events: [DiagnosticEventRecord]`; subscribes to `observeDiagnosticEvents` via `ObservationStream`/AsyncStream; `share()` renders filtered text; `clear()`).
- Create: `Spud/Scenes/Preferences/About/Logs/DiagnosticLogView.swift` + `DiagnosticLogRowView.swift` + `DiagnosticLogDetailView.swift`.
- Test: `SpudDataKitTests`/`SpudTests` for the view model's filter/share-text logic (pure, unit-testable); snapshots in Phase-4 Task 14.

Behavior: newest-first list; category chips (multi-select) + level segmented (Debug/Info/Notice/Errors); search field; row shows time + colored level glyph **with text equivalent** + category + message; tap → detail (pretty JSON metadata, instance, full timestamp); toolbar Share (share sheet of filtered text) + Clear (confirmation). Accessibility: combined row label, chip labels, no color-only meaning, Dynamic Type.

- [ ] **Step 1: Failing test** — view-model `shareText(for:)` produces one line per event `"<iso8601> [<level>] <category> <event> — <message> (<instance>)"`; level filter drops below-threshold events from `events`.
- [ ] **Step 2–4:** run-fail, implement view model + views, run-pass.
- [ ] **Step 5:** build app green; swiftformat; **commit** `feat(diagnostics): Event Log viewer (list + detail + filter + share + clear)`.

### Task 13: `SystemLogView` (fixed OSLog tail) + host both tabs

**Files:**
- Create: `Spud/Scenes/Preferences/About/Logs/SystemLogView.swift`
- Modify: `Spud/Scenes/Preferences/About/PreferencesAboutView.swift` — replace `PreferencesLogsView`'s body with a `Picker`/segmented control switching Event Log / System Log; keep the same `NavigationLink` entry.

Fixes vs. today: append `\n` between entries; show level; level + category filter; window picker (Last hour / 24h / Since launch); Copy + Share; surface the `OSLogStore` `catch` as an inline error instead of a blank screen; non-editable text.

- [ ] **Step 1:** Implement `SystemLogView` (reuse the existing `OSLogStore` read, fixed); host both tabs.
- [ ] **Step 2:** Build app green; manual check both tabs render, filter, share.
- [ ] **Step 3:** swiftformat; **commit** `feat(diagnostics): fix System Log tab + host both tabs in About`.

### Task 14: Snapshots + accessibility pass

**Files:**
- Create: `SpudSnapshotTests/DiagnosticLogSnapshotTests.swift`
- Test plan: `SpudSnapshots`

- [ ] **Step 1:** Snapshot Event Log (mixed levels), category-filtered, level-filtered, empty state, detail, System Log — light + dark. Pin a device config where possible; otherwise record on iPhone 17 Pro / iOS 26.3.1 (first run records + fails, rerun verifies; one class at a time; `git annex` restage caveats per CLAUDE.md).
- [ ] **Step 2:** Accessibility review (VoiceOver labels, Dynamic Type at XXL, contrast) — adjust views; re-verify.
- [ ] **Step 3:** `git add` only the new refs (explicit paths); **commit** `test(diagnostics): viewer snapshots + a11y`.

**Phase 4 acceptance:** About → Logs shows a durable, filterable, shareable Event Log + a fixed System Log; survives relaunch; accessible.

---

## PHASE 5 — Docs

### Task 15: Feature docs + README + CLAUDE.md

**Files:**
- Create: `docs/features/diagnostics-logging.md` — capability, rules, **Scenarios** (Given/When/Then): view logs; filter by site/category/level; diagnose a failed vote (the `op.permanentRollback` story); export for a bug report; logs survive relaunch. `Status:` accurate; `Surfaces:` iphone, ipad.
- Modify: `docs/features/README.md` — capability table row + by-area map entry.
- Modify: `Spud/CLAUDE.md` — Persistence: latest migration `v26_diagnosticEvent`; note durable diagnostic log + instrumented outbox path; reconcile the `getSite 403` note (now carries instance).

- [ ] **Step 1:** Write the docs (no `.swift` links; follow `_TEMPLATE.md`).
- [ ] **Step 2:** **commit** `docs: diagnostics-logging feature + README + CLAUDE.md (v26)`.

**Phase 5 acceptance:** docs reflect shipped behavior; README sections reconciled.

---

## Self-review notes (author)

- **Spec coverage:** every spec section maps to a task — store (T1–4), recorder (T5), prune (T6), outbox instrumentation incl. the headline silent-rollback event (T7–8), site host + background tasks (T9–11), viewer + a11y (T12–14), docs (T15). The clear-cut correctness items (getSite host T9; orphaned-no-service event T7) are covered. Speculative behavior changes are explicitly out (spec Non-goals).
- **Type consistency:** `DiagnosticLogging.record(...)` signature, `DiagnosticLogFilter` fields, `DiagnosticCategory`/`DiagnosticLevel` cases, and event names (`op.permanentRollback`, `op.permanentPark`, `site.fetchFailed`, `drain.start/finish`) are used identically across tasks.
- **Deferred:** the actual *fix* for the vote concern (if reproduction shows one) is a Phase-6 follow-up gated on evidence from this instrumentation — not in this plan.
