# Observability — durable diagnostic log + better in-app log viewer

- **Date:** 2026-06-29
- **Status:** design — pending implementation
- **Surfaces:** `iphone`, `ipad`
- **Targets touched:** `Spud`, `SpudDataKit`
- **Replaces/updates docs:** new `docs/features/diagnostics-logging.md`; README capability table + by-area map

## Background — why this exists

The user reported two intertwined concerns:

1. **"I upvoted a post while offline. Later, back online, I saw that same post on my feed with no vote."** Is the vote/save/hide mutation outbox silently dropping offline votes?
2. **The About → Logs screen shows a recurring `Fetch site failed 403`** but doesn't say *which* instance is failing, and the viewer itself is barely usable.

A read-only investigation (see the systematic-debugging Phase-1 findings folded into this spec) established the decisive fact: **the entire outbox drain path emits zero log lines.** `OutboxService.drain` — enqueue, attempt, success, transient-retry, and the **permanent-rollback that discards a user's vote** — has no `Logger` calls at all. `ComposerOutboxService` is identically dark. So the honest answer to "is the outbox working?" is *we cannot tell from the logs*. The investigation cannot conclude without first instrumenting the system — which is exactly what systematic debugging prescribes (add diagnostic instrumentation at component boundaries, reproduce, then analyze).

Findings that are already provable from code:

- **Feed re-import clobbering the vote — ruled out.** The reconciliation guard (`pendingOutboxKinds`, `PendingOperationWrites.swift:362`) is active during feed imports (`PostImporter.upsertPost` defaults `respectsPendingOutbox: true`) and preserves pending vote/save/hide/delete state. Not the culprit.
- **Rollback on a permanent 403 — real, conditional, and it *does* toast.** A 403-while-online classifies `.permanent` (`OutboxFailureClass.swift`: `(400..<500)` minus 408/429), rolls the vote back to baseline, and emits a `"Couldn't vote"` toast via `OutboxService.emitFailure` → `MainWindow.startObservingOutboxFailures` → `presentOutboxFailureToast`. An *offline* failure classifies `.transient` (`if !isOnline { return .transient }`) and is retried. So the vote only vanishes if a genuine 403 returns *after* reconnect — which directly implicates the recurring `getSite` 403 instance.
- **Orphaned pending ops — a real but narrow hole.** The outbox is built lazily on first vote/save/hide. If `accountSiteIds()` returns nil at construction, `outboxService()` returns nil and `drainPendingOutbox()` is a silent no-op. It is *re-attempted every foreground*, so the only true orphan is an account that is permanently gone (ops then moot) — but today the skip is entirely silent and undiagnosable.

The conclusion that shapes this design: **the highest-leverage work is to make the background-task and outbox machinery observable, durably and across app relaunches, and to give the user a viewer that can actually answer "what happened to my vote / which site fails."** Behavioral fixes (beyond the clear-cut correctness items below) are deferred until the new instrumentation lets the user reproduce and we can root-cause with evidence.

## Goals

- **Every background task is observable.** Each background/async task records its lifecycle (start, finish, outcome, key counts) to OSLog *and*, for the diagnostically important ones, to a durable event log.
- **Both outboxes are fully observable.** Every op lifecycle event — enqueue, drain start/finish, attempt, success, transient retry, **permanent rollback (mutation) / permanent park (content)**, classification decision, reconciliation-guard skip — is recorded. The silent data-loss path is never silent again.
- **"Which site fails" is answerable.** Site-info fetch failures (the 403) record the **instance host** (non-secret) alongside the HTTP status — in OSLog and the durable log.
- **The history survives relaunch.** The durable log persists in GRDB, so the user can open About → Logs *after* a restart and still see what the outbox did to their offline vote.
- **A genuinely good in-app viewer.** Filter by category and level, search, per-entry detail, copy/share/export, clear — for the durable event log; plus a fixed, usable OSLog tail for the live session.
- **Clear-cut correctness fixes, gated narrowly.** Add the instance host to the `getSite` failure log; make the silent permanent-rollback observable (durable error event). No speculative behavior change to the outbox until evidence justifies it.

## Non-goals (this iteration)

- **Changing outbox classification or retry/rollback behavior.** The investigation is not yet conclusive; we instrument first. Any behavior change waits for a reproduction with the new logging (a follow-up slice). The one exception is *observability of* the rollback, which is added here.
- **Capturing widget/extension background runs.** The durable log lives in the App Group DB so extensions *could* write later, but this iteration scopes writers to the main app process only.
- **Remote/automatic log upload or crash reporting.** Export is a manual, user-initiated share-sheet action. Nothing leaves the device automatically.
- **A 403 back-off / 403-aware scheduler policy.** Tracked separately (`spud_scheduler_getsite_403`); this spec makes the 403 *visible*, not handled.
- **Replacing OSLog.** OSLog stays the primary firehose; the durable log is a curated, cross-launch subset of high-value lifecycle events.

## Architecture

### One durable store: `diagnosticEvent` (GRDB, migration `v26`)

A single append-only GRDB table records curated lifecycle events. GRDB is the right mechanism: it is the codebase's persistence layer, it lives in the App Group container (extensions could contribute later), it is queryable for the viewer's filters, and it is observable for a live-updating list. OSLog cannot do cross-relaunch in-app viewing (`OSLogStore(scope: .currentProcessIdentifier)` only ever sees the current process), which is the whole point.

```
diagnosticEvent
  id          INTEGER PK
  timestamp   DOUBLE  NOT NULL          -- epoch seconds (event time)
  category    TEXT    NOT NULL          -- DiagnosticCategory.rawValue
  level       INTEGER NOT NULL          -- DiagnosticLevel.rawValue (0=debug,1=info,2=notice,3=error)
  event       TEXT    NOT NULL          -- short machine name, e.g. "op.permanentRollback", "drain.start", "site.fetchFailed"
  message     TEXT    NOT NULL          -- human-readable one-liner
  instance    TEXT                      -- instance host (non-secret), nil for account-agnostic events
  metadata    TEXT                      -- optional JSON object of structured fields (httpStatus, entityType, entityServerId, attempts, error, counts)
```

Index: `CREATE INDEX index_diagnosticEvent_on_timestamp ON diagnosticEvent(timestamp)` (the viewer reads newest-first and filters by time/category/level).

Migration: **`v26_diagnosticEvent`** as the next case in `AppDatabase+Migrations.swift` (current head `v25_offlineWebArchive`). Never edit a shipped migration.

**Retention.** The table is capped to keep it bounded: prune to the **most recent 10,000 rows** and **drop rows older than 14 days**, whichever is tighter, run opportunistically at service init (app launch) and after large bursts. Pruning is a single `DELETE` keyed on `timestamp` / `id`; cheap.

**Privacy.** The durable log is local-only and user-owned. The **instance host** (e.g. `lemmy.world`) is public, non-secret, and exactly what aids diagnosis — it is stored in clear. We **never** store auth tokens, passwords, or cookies (we don't log them today either). The raw `accountKeychainId` is **not** stored; if an event must distinguish accounts on the same instance, a short non-secret label goes in `metadata` (never the keychain id). Export is a deliberate user action; the exported text carries only what is in the table (instance host + messages + metadata), so it is safe to paste into a bug report.

Records / helpers (mirroring existing conventions):
- `Services/AppDatabase/Records/DiagnosticEventRecord.swift` — the record + column inference + `didInsert`.
- `Services/AppDatabase/DiagnosticEventWrites.swift` — `AppDatabase` extension: `insertDiagnosticEvent`, `recentDiagnosticEvents(filter:)`, `pruneDiagnosticEvents(now:)`, `clearDiagnosticEvents`.
- `Services/AppDatabase/DiagnosticEventObservations.swift` — `observeDiagnosticEvents(filter:) -> AsyncStream<[DiagnosticEventRecord]>` using `.async(onQueue: .global(qos: .userInitiated))`.

### The recorder: `DiagnosticLog` (`Sendable`, dual-sink)

A lightweight value type that fans each recorded event to **both** sinks so call sites stay single-line:

1. **OSLog** — emits through the appropriate `Logger` category at the mapped `OSLogType`, so the System Log tab and Console.app still see everything.
2. **The durable table** — appends a `diagnosticEvent` row.

```swift
public enum DiagnosticCategory: String, Sendable, CaseIterable {
    case outbox          // mutation outbox (vote/save/hide)
    case composerOutbox  // content outbox (comment/post/DM drafts + sends)
    case scheduler       // 5-min SchedulerService tick
    case site            // getSite / site-info fetch (the 403)
    case offlineDownload // OfflineDownloadService
    case unread          // UnreadCountService
    case spotlight       // Community/Content Spotlight indexers
    case lifecycle       // launch / foreground / account-applied
}

public enum DiagnosticLevel: Int, Sendable, Comparable {
    case debug = 0, info = 1, notice = 2, error = 3
    // maps to OSLogType.debug/.info/.default/.error
}

public protocol DiagnosticLogging: Sendable {
    func record(
        category: DiagnosticCategory,
        level: DiagnosticLevel,
        event: String,
        message: String,
        instance: String?,
        metadata: [String: String]?
    ) async
    func recent(_ filter: DiagnosticLogFilter) async -> [DiagnosticEventRecord]
    func clear() async
}

public struct DiagnosticLogFilter: Sendable, Equatable {
    public var categories: Set<DiagnosticCategory>?  // nil = all
    public var minimumLevel: DiagnosticLevel          // default .debug
    public var searchText: String?                    // matches message/event/instance/metadata
    public var limit: Int                             // default 1000
}
```

`DiagnosticLog` is a `struct` (or `final class`, `Sendable`) wrapping `AppDatabase` plus a `Logger`-category resolver. `record(...)` is `async` and callers `await` it: the SQLite insert runs on the AppDatabase writer queue, so awaiting inside an actor (e.g. `OutboxService`) does not block other actors and preserves event ordering. A spy implementation (`DiagnosticLogSpy`) backs unit tests.

Category → `Logger` mapping reuses existing categories where present and adds the two missing ones:
- New `Logger.outbox` and `Logger.composerOutbox` categories in `SpudDataKit/Utils/Logger.swift` (both currently have **no** category — they never imported `Logger`).
- Reuse `Logger.schedulerService`, `Logger.offlineDownloadService` for those.
- `site` → `Logger.lemmyService` (where `getSite` already logs). `unread` → a new `Logger.inbox` (today it wrongly borrows `lemmyService`). `spotlight` → `Logger.app`. `lifecycle` → `Logger.app`.

### Event taxonomy (the curated set)

Only high-value lifecycle events go to the durable table (OSLog still gets the chatty stuff). Canonical event names per category:

- **outbox / composerOutbox:** `op.enqueue` (info), `drain.start` (info; trigger + due count), `op.attempt` (debug), `op.success` (info), `op.transientRetry` (notice; error, attempt#, nextAttemptAt), `op.permanentRollback` (mutation, **error**) / `op.permanentPark` (content, **error**), `drain.finish` (info; succeeded/retried/rolled-back counts), and for content: `dedup.adopt` (notice), `inflight.skip` (debug). Each carries `instance` + structured `metadata` (entityType, entityServerId, httpStatus, attempts, error).
- **scheduler:** `tick.start` (debug), `account.fetch` (debug; per account, with instance), `tick.finish` (debug; counts).
- **site:** `site.fetchFailed` (**error**; instance, httpStatus, error) — the 403. `site.fetchOK` (debug; instance) optional.
- **offlineDownload:** `download.start` (info; feed, target count), `download.itemFailed` (notice), `download.finish` (info; saved counts) / `download.cancelled` (info).
- **unread:** `refresh.start` (debug), `refresh.finish` (debug; count) / `refresh.failed` (error).
- **spotlight:** `reindex.finish` (debug; community/content counts) / `reindex.failed` (error).
- **lifecycle:** `launch` (info), `foreground` (info), `accountApplied` (info; instance).

### Instrumentation points (the writers)

`DiagnosticLog` is injected (via the existing dependency container) into every writer:

1. **`OutboxService`** (mutation outbox) — record the full lifecycle; the **`op.permanentRollback`** event is the headline (it makes the silent vote-loss observable and durable). Pass the account's instance host into the service at construction so events carry it.
2. **`ComposerOutboxService`** (content outbox) — the same lifecycle with `op.permanentPark`, plus `dedup.adopt` / `inflight.skip`.
3. **`SchedulerService`** — bracket the 5-min tick; per-account `account.fetch` with instance.
4. **`LemmyService.getSiteInfo`** — add the **instance host** to the existing OSLog error line (`logger.error("Fetch site failed. instance=\(host, privacy: .public)...")`) and record a durable `site.fetchFailed`. Host comes from `await appDatabase.accountInstanceActorId(forKeychainId:)` → `InstanceActorId(from:)?.hostWithPort` (the async, actor-safe path already used in `resolveObject`).
5. **`UnreadCountService.refresh`** — start/finish/failed; fix the category (use new `Logger.inbox`).
6. **`OfflineDownloadService`** — start (feed/account/target), per-item failures, finish/cancel with counts.
7. **`SceneDelegate` / `MainWindow`** — `lifecycle.launch`, `lifecycle.foreground`, `lifecycle.accountApplied` so drains/refreshes can be correlated in time.
8. **Spotlight indexers** — finish-with-counts + keep existing error logs (now also durable).

**Orphaned-pending-ops instrumentation.** Where `outboxService()` / `composerOutbox()` returns nil while pending rows exist, record a durable `error` event (`drain.skippedNoService`, instance/account in metadata) so the otherwise-silent stuck state is diagnosable. No behavior change (it already re-attempts each foreground); this is observability only.

### The viewer redesign — About → Logs

Replace the current one-`TextEditor` `PreferencesLogsView` (`Spud/Scenes/Preferences/About/PreferencesAboutView.swift`) with a proper SwiftUI viewer (stays SwiftUI to match the About screen) backed by a segmented control:

**Tab 1 — Event Log (durable, default).** A live list of `diagnosticEvent` rows, newest first, observed from GRDB:
- **Filter** by category (multi-select chips) and minimum level (Debug / Info / Notice / Errors).
- **Search** box matching message / event / instance / metadata.
- Each row: time, a level glyph with color *and* a text equivalent (a11y), category, message. Tap → **detail** showing full metadata (pretty-printed JSON), instance, exact timestamp.
- **Share/Export** (toolbar): renders the current (filtered) view to text and presents the system share sheet. **Clear** (with confirmation) empties the table.
- Survives relaunch — the defining capability.

**Tab 2 — System Log (OSLog tail, live session).** The fixed version of today's viewer:
- Fix the **missing separator** (entries currently smear into one blob — append `\n`).
- Show the **level** per entry; add a level filter and category filter.
- **Configurable window** (Last hour / Last 24h / Since launch) instead of the hard-coded 1h.
- **Copy / Share**; non-editable text; **surface the `catch`** (today an empty `catch {}` silently yields a blank screen) as an inline error.

**Accessibility (part of done).** VoiceOver labels on filter chips and the segmented control; level conveyed by text not color alone; Dynamic Type throughout; the share and clear actions labeled; the list rows expose a combined label (time + level + category + message). Covered deliberately (snapshots don't catch a11y).

## Data flow (offline vote, the user's scenario — now observable)

```
vote offline → enqueue → diagnosticEvent(outbox, info, "op.enqueue", instance=…)
            → drainOnce → perform throws URLError → classify(isOnline:false)=transient
            → op.transientRetry recorded (waits)
reconnect   → reachability flip → drain.start recorded
            → perform → 403 → classify(isOnline:true)=permanent
            → rollbackOutboxOperation + op.permanentRollback recorded (ERROR, instance, httpStatus=403)
            → "Couldn't vote" toast (existing)
later, in About → Logs (even after relaunch): the op.permanentRollback row explains
exactly what happened to the vote and on which instance.
```

## Testing

Unit (`SpudDataKitTests`, Swift Testing; in-memory `AppDatabase` + `DiagnosticLogSpy`):
- `v26` migration creates the table + index.
- `insertDiagnosticEvent` / `recentDiagnosticEvents(filter:)` — category, level, and search filtering; newest-first ordering; limit.
- `pruneDiagnosticEvents` — keeps ≤10k rows and drops >14-day-old rows.
- `DiagnosticLog.record` writes a row **and** (assert via spy/category) targets the right `Logger` category.
- **`OutboxService` regression:** with a fake performer forced to throw a 403, assert an `op.permanentRollback` event is recorded (instance + httpStatus in metadata) and the baseline is restored — the previously-silent path is now proven observable. Transient path records `op.transientRetry`; success records `op.success`.
- **`ComposerOutboxService`:** permanent failure records `op.permanentPark` and keeps the row; `dedup.adopt` recorded on adoption.
- `getSiteInfo` failure records `site.fetchFailed` carrying the instance host.

Snapshot (`SpudSnapshots`, iPhone 17 Pro portrait, iOS 26.3.1; pin a config for device independence where possible):
- Event Log list (mixed levels), category-filtered, level-filtered, empty state, light + dark.
- Event detail (with metadata), light + dark.
- System Log tab, light + dark.

UI/manual: trigger an offline vote against a 403 instance (stub), reconnect, then open About → Logs and confirm the `op.permanentRollback` row is present after a relaunch. (Mind the one-booted-sim flake.)

## Files (anticipated)

New — SpudDataKit:
- `Services/AppDatabase/Records/DiagnosticEventRecord.swift`
- `Services/AppDatabase/DiagnosticEventWrites.swift`
- `Services/AppDatabase/DiagnosticEventObservations.swift`
- `Services/Diagnostics/DiagnosticLog.swift` (+ `DiagnosticLogging`, `DiagnosticCategory`, `DiagnosticLevel`, `DiagnosticLogFilter`)
- `Services/AppDatabase/AppDatabase+Migrations.swift` — `v26_diagnosticEvent`
- `Utils/Logger.swift` — add `outbox`, `composerOutbox`, `inbox` categories

Modified — SpudDataKit:
- `Services/Outbox/OutboxService.swift`, `Services/Outbox/ComposerOutboxService.swift` — inject + emit events; pass instance host.
- `Services/Scheduler/SchedulerService.swift`, `Services/Lemmy/LemmyService.swift` (getSite host), `Services/Inbox/UnreadCountService.swift`, `Services/Offline/OfflineDownloadService.swift` — emit events.
- Dependency container wiring for `DiagnosticLog`.

New — Spud (app):
- `Scenes/Preferences/About/Logs/DiagnosticLogView.swift` (+ row, detail, filter model)
- `Scenes/Preferences/About/Logs/SystemLogView.swift` (the fixed OSLog tail)

Modified — Spud (app):
- `Scenes/Preferences/About/PreferencesAboutView.swift` — host the new segmented viewer.
- `Integration/SceneDelegate.swift`, `Scenes/MainWindow/MainWindow.swift`, Spotlight indexers — lifecycle events.

`make project` (XcodeGen) after adding files.

## Docs to update on completion

- New `docs/features/diagnostics-logging.md` — capability + Given/When/Then scenarios (view logs; filter by site; diagnose a failed vote; export for a bug report; logs survive relaunch).
- `docs/features/README.md` — capability table + by-area map.
- `Spud/CLAUDE.md` — Persistence section: latest migration `v26_diagnosticEvent`; note the durable diagnostic log + the now-instrumented outbox path.
- Reconcile `spud_scheduler_getsite_403` follow-up note (the 403 is now visible with its instance).

## Rollout / phasing (for the implementation plan)

1. **Durable store + recorder (headless):** `v26` table, record, writes/observations, `DiagnosticLog` + spy, prune, Logger categories, unit tests. No callers yet.
2. **Instrument the outboxes:** wire `DiagnosticLog` into `OutboxService` + `ComposerOutboxService` (full lifecycle incl. permanent rollback/park, instance host), unit tests with spy. The vote-diagnosis lands here.
3. **Instrument background tasks + site failures:** Scheduler, getSite instance host + `site.fetchFailed`, UnreadCountService (+ category fix), OfflineDownloadService, SceneDelegate/MainWindow lifecycle, Spotlight; orphaned-no-service event.
4. **The viewer:** Event Log + System Log tabs, filter/search/detail/share/clear, OSLog fixes, accessibility, snapshots.
5. **Docs refresh.**

## Open risks

- **Log volume / write amplification.** Curated event set + level discipline keeps the table small; the 10k/14-day prune bounds it. `op.attempt` is `debug` and could be dropped from the durable sink if volume is a problem (kept in OSLog).
- **Inserting from many isolation contexts.** `DiagnosticLog` must be safely callable from actors, `@MainActor`, and nonisolated background code; the AppDatabase writer queue serializes the inserts, so this is sound, but each new call site must `await` (don't fire-and-forget in a way that drops ordering during a drain).
- **Not regressing the shipped outboxes.** Instrumentation is additive (no change to classify/rollback/retry control flow); the `OutboxService` permanent-path test guards the behavior while adding the event.
- **Snapshot drift.** New SwiftUI viewer snapshots are runtime-sensitive — record on iPhone 17 Pro / iOS 26.3.1.
