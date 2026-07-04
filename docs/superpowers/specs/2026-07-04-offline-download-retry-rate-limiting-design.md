# Offline download — retries and rate limiting

- **Date:** 2026-07-04
- **Status:** design — pending implementation
- **Surfaces:** `iphone`, `ipad` (behavior + logs; one new terminal message string)
- **Targets touched:** `SpudDataKit`
- **Replaces/updates docs:** `docs/features/offline-download.md` (add retry /
  rate-limit / partial-success behavior + a Scenario) and the README index
  (capability table row + by-area map)

## Summary

An offline feed download pages the feed then fetches each post's comments +
images. Today the **page-fetch phase aborts the entire download on the first
error** — a single transient hiccup (the observed `unknownServerError(503)`, a
timeout, or a rate-limit) throws out of `fetchPages`, hits `run`'s catch, and
ends the run as `.failed` with "Could not download the feed", discarding every
page already persisted. There is also **no back-off anywhere**, so naive retries
would risk a retry storm against a struggling instance.

This adds graceful handling: a proactive request **pacer** (spaces all requests
so we never hammer the host, and injects a global cool-down when the server
signals pushback) plus per-request **retry with jittered exponential back-off**
on transient failures. When a page permanently fails **after** some pages already
landed, the download keeps what it has, finishes the content phase for those
posts, and reports a partial success — only a zero-pages failure is still fatal.

## Background — verified current state

- `OfflineDownloadService` (an `actor`, `SpudDataKit/Services/Offline/`) runs two
  phases in `run(...)`:
  1. `fetchPages(...)` — a `repeat/while` loop calling
     `lemmyService.fetchFeed(feed, pageCursor:showNsfw:)` (each call persists a
     page to GRDB and returns the next cursor). It stops on nil cursor,
     `maxConsecutiveEmptyPages` no-growth pages, the `maxPages` backstop, or
     reaching `maxPosts`. **Any thrown error propagates out.**
  2. Content phase — a bounded `TaskGroup` (cap `contentConcurrency = 4`, a
     sliding window) where `processTarget(...)` fetches each post's comment tree
     (`fetchComments`) and warms its thumbnail + full image via
     `drainImageFetch(imageService, ...)`, plus an optional web-archive capture.
- `run`'s error handling (`OfflineDownloadService.swift:343-378`): `fetchPages`
  is wrapped in `do/catch`; `CancellationError` → `.cancelled` (keeps partial),
  **any other error** → logs "Offline download failed during page fetch" and
  emits `.failed` ("Could not download the feed."). Posts persisted by earlier
  pages remain in GRDB but the run reports total failure.
- The content phase is already **best-effort per item**: `processTarget` swallows
  a `fetchComments` throw (returns `false` → `download.itemFailed` diagnostic,
  still counts the post completed) and `drainImageFetch` already swallows image
  errors. So one bad post never aborts the run — only page-fetch does.
- **Reusable infra already exists:**
  - `OutboxFailureClass.classify(_ error:isOnline:) -> .transient | .permanent`
    (`Services/Outbox/OutboxFailureClass.swift`) already classifies exactly our
    case: `unknownServerError(503)` → `.transient`; 5xx / 408 / 429 / `rate_limit`
    / `URLError` → `.transient`; 4xx (except 408/429) / auth / invalid-content →
    `.permanent`. We reuse it verbatim — no new classifier.
  - `SchedulerBackoff` (`Services/Scheduler/SchedulerBackoff.swift`) is the
    "time is a parameter" precedent for a pure, testable back-off value type
    (its ~5m-doubling curve is scheduler-scale and NOT reused here; we want
    seconds-scale in-loop back-off).
- `OfflineDownloadProgress` (`Services/Offline/OfflineDownloadProgress.swift`) is
  a `Sendable` value type with `phase`, `postsFetched`, `totalPosts`,
  `itemsCompleted`, `failureMessage`. `.finished` → `fractionCompleted == 1`.
- `DiagnosticLogging` is already injected into the service; the content phase
  records `download.itemFailed` / `download.cancelled` etc. under category
  `.offlineDownload`.
- Web-archive capture (`webArchiveCapturer`) loads the post's **external link**
  host via `WKWebView` — a different host from the Lemmy instance, and already
  `@MainActor` + self-serializing with its own timeout.

## Goals

- A transient page-fetch failure (503/5xx/timeout/429/rate-limit) is retried with
  bounded jittered exponential back-off instead of aborting the download.
- Requests are proactively spaced (a global minimum interval across all workers)
  so the download never bursts the host, and a server pushback signal (429/503/
  rate-limit) triggers a global cool-down that all in-flight workers observe.
- A page that permanently fails **after** ≥1 page landed → keep the persisted
  posts, run the content phase on them, and finish with a partial-success notice.
  Only a zero-pages failure remains `.failed`.
- Per-post content fetches (comments/images) retry transient failures too, still
  best-effort (a permanently-failing item is swallowed exactly as today — just
  after retries, not on the first hiccup).
- Observable: retries and partial completion are recorded in About → Logs.

## Non-goals (this iteration)

- **No general shared "polite executor"** for scheduler/outbox/live-feed. The
  pacer + retry are scoped to `Services/Offline/` (reusing `OutboxFailureClass`).
  Lifting them into a shared component is a later, separate change (YAGNI) and
  keeps this off the two shipping outbox/scheduler subsystems.
- **No adaptive concurrency** (auto-shrinking the fan-out on pushback). The
  `penalize` global cool-down is the pushback response; `contentConcurrency`
  stays fixed at 4. Adaptive fan-out is deferred.
- **No web-archive throttling change.** Archive capture hits the external link
  host (not the instance) and keeps its own timeout; it does not go through the
  instance pacer.
- **No persisted retry state / migration.** All retry + pacing state is per-run,
  in-memory.
- **No "pause until reachable" wait-loop.** v1 passes `isOnline: true` to
  `classify` (a download is user-initiated in the foreground; network errors are
  transient by classification regardless), so a mid-download disconnect still
  backs off. Consulting live `ReachabilityMonitoring` to hold until online is a
  noted enhancement, not built here.

## Design

Two small, independently testable pieces under `Services/Offline/`, wired into
`OfflineDownloadService.run`.

Every operation we retry is an **idempotent read** — `fetchFeed` (same cursor),
`fetchComments`, and image GETs all re-run safely with no side effect beyond
re-upserting the same rows. That is why retry belongs here and not behind
`OutboxService`: the outbox exists precisely to guard *non-idempotent* mutations
(votes/creates) from re-send, whereas a download only reads.

### 1. `RequestPacer` (actor) — proactive throttle + reactive cool-down

One instance per download run, shared by the page loop and all content workers.
Enforces a **global** minimum interval between request kickoffs (independent of
the 4 concurrent workers) and a cool-down injected on server pushback.

```swift
/// Paces outbound requests for one offline-download run so all workers together
/// never exceed one request per `minInterval`, and a server pushback (429/503/
/// rate-limit) delays every subsequent request by a cool-down. Injectable clock
/// + sleep make it deterministic in tests.
actor RequestPacer {
    private let minInterval: Duration
    private let now: @Sendable () -> ContinuousClock.Instant
    private let sleep: @Sendable (ContinuousClock.Instant) async throws -> Void
    private var nextPermitAt: ContinuousClock.Instant

    /// Reserve the next slot (synchronous, actor-isolated bump), returning the
    /// instant to wait until; the caller sleeps OUTSIDE the actor.
    private func reserve() -> ContinuousClock.Instant { /* max(now, nextPermitAt); nextPermitAt = slot + minInterval; return slot */ }

    func acquire() async throws {
        let deadline = reserve()
        try await sleep(deadline)   // sleep is NOT actor-isolated work
    }

    /// Push every subsequent permit out by `cooldown` (server asked us to slow).
    func penalize(_ cooldown: Duration) {
        let candidate = now().advanced(by: cooldown)
        if candidate > nextPermitAt { nextPermitAt = candidate }
    }
}
```

Key correctness point: `acquire` must NOT sleep while holding the actor —
`reserve()` is the only actor-isolated step (a synchronous bump of
`nextPermitAt`); the `await sleep(deadline)` happens after. Otherwise the pacer
serializes into a bottleneck. (In production `sleep(deadline)` is
`ContinuousClock().sleep(until: deadline)`; tests inject a fake that advances
logical time and records the requested deadlines.)

### 2. `withRetry` — bounded jittered exponential back-off

A free `async` function wrapping a single network op. Uses `OutboxFailureClass`
to decide retry, and calls `pacer.penalize` on pushback so back-off (per-request)
and cool-down (global) compose.

```swift
/// Run `operation`, retrying transient failures (per `OutboxFailureClass`) with
/// jittered exponential back-off up to `maxAttempts`. On a server-pushback error
/// (429/503/rate-limit) also penalizes the shared pacer. Rethrows a permanent
/// error immediately and the last error once attempts are exhausted.
func withRetry<T>(
    maxAttempts: Int,
    baseDelay: Duration,
    maxDelay: Duration,
    pushbackCooldown: Duration,
    pacer: RequestPacer,
    isOnline: Bool = true,
    sleep: @Sendable (Duration) async throws -> Void,
    jitter: @Sendable (ClosedRange<Double>) -> Double,
    onRetry: @Sendable (_ attempt: Int, _ delay: Duration, _ error: Error) -> Void = { _, _, _ in },
    operation: () async throws -> T
) async throws -> T
```

- On throw: `Task.checkCancellation()` first (a cancelled run must not be treated
  as a retryable failure — rethrow `CancellationError`). Then
  `OutboxFailureClass.classify(error, isOnline: isOnline)`:
  - `.permanent` → rethrow immediately.
  - `.transient` → if `attempt == maxAttempts` rethrow; else compute
    `delay = min(maxDelay, baseDelay * 2^(attempt-1))` with **full jitter**
    (`delay * jitter(0...1)`), call `onRetry(...)`, and if the error is a
    pushback class call `pacer.penalize(pushbackCooldown)`, then
    `await sleep(delay)` and loop.
- "Pushback" = 429, 503, or a `rate_limit`-prefixed structured server error
  (small local predicate over `LemmyServiceError`/`LemmyApiError`; the broader
  transient set — other 5xx, timeouts — retries but does not add a global
  cool-down).
- `jitter` is injected (`Double.random(in:)` in prod; a fixed value in tests) so
  the back-off schedule is deterministic under test.

### 3. Integration in `OfflineDownloadService`

`run` builds one `RequestPacer` and threads it + a retry closure into both
phases. New tunables as `static` constants on the service (starting values):

| Constant | Value | Note |
|---|---|---|
| `minRequestInterval` | `.milliseconds(200)` | ≈5 req/s ceiling across all workers |
| `maxRetryAttempts` | `4` | attempts per request incl. the first |
| `retryBaseDelay` | `.milliseconds(500)` | 0.5s → 1s → 2s (× jitter) |
| `retryMaxDelay` | `.seconds(30)` | back-off cap |
| `serverPushbackCooldown` | `.seconds(8)` | global cool-down on 429/503/rate-limit |

**Phase 1 (`fetchPages`)** — the `fetchFeed` call becomes:

```swift
try await pacer.acquire()
let nextCursor = try await withRetry(...pacer...) {
    try await lemmyService.fetchFeed(feed, pageCursor: cursor, showNsfw: showNsfw)
}
```

`fetchPages` gains a partial outcome. Rather than only returning `postsFetched`,
it signals whether the loop ended early on a permanent error. Simplest shape:
`fetchPages` catches the rethrow from `withRetry` **inside the loop**:

- `CancellationError` → rethrow (unchanged; `run` maps to `.cancelled`).
- other (permanent / retries exhausted): if `persistedCount > 0` → record
  `download.pageFetchIncomplete` (notice; metadata: posts kept), `break` the loop
  and return `(postsFetched: persistedCount, wasPartial: true)`; if
  `persistedCount == 0` → rethrow so `run`'s existing catch emits `.failed`.

So `fetchPages` returns e.g. `(count: Int, wasPartial: Bool)` (or throws only the
zero-pages / cancellation cases). `run` carries `wasPartial` to the terminal.

**Phase 2 (`processTarget`)** — `fetchComments` and each `drainImageFetch` are
wrapped in `pacer.acquire()` + `withRetry`, still best-effort: `processTarget`
keeps its existing `do/catch`-swallow, so a request that still fails after
`maxRetryAttempts` is swallowed exactly as today (comments → `false` →
`download.itemFailed`; image → ignored). The retry just means one transient blip
no longer loses that item. `drainImageFetch` gets an internal retry wrapper (it
currently swallows; now it retries transient then swallows). Web-archive capture
is unchanged and not paced.

Static `processTarget` currently takes its collaborators as parameters; it gains
`pacer` + the retry tunables (passed down from `run`) so it stays `static` and
testable.

### 4. Terminal state — partial success

Add one field to `OfflineDownloadProgress` (additive, defaulted — non-breaking):

```swift
/// A non-fatal notice about a completed run (e.g. not every feed page could be
/// reached, so fewer posts were downloaded than requested). Set only on
/// `.finished`; nil for a fully-complete run. Distinct from `failureMessage`
/// (fatal) — `.finished` still means `fractionCompleted == 1`.
public var warningMessage: String?
```

`run` emits the terminal `.finished` with `warningMessage` set when
`wasPartial` (e.g. "Downloaded \(postsFetched) posts — some of the feed couldn't
be reached."). A full run leaves it nil. The UI (progress sheet) shows the notice
on completion; deriving the exact copy/placement is a thin UI follow-up but the
data-layer contract is set here. `.failed` (zero pages) is unchanged.

## Data flow

Transient page hiccup mid-run, then a permanent failure with posts already saved:

```
fetchPages: page 1 → acquire (paced) → fetchFeed OK (10 posts)
            page 2 → acquire → fetchFeed throws 503 (transient)
                   → withRetry: classify=.transient, pushback → pacer.penalize(8s),
                     onRetry → download.retry (attempt 1, delay ~0.5s), sleep, retry
                   → fetchFeed OK (20 posts)          # blip absorbed
            ...
            page K → acquire → fetchFeed throws 403 (permanent, after retries N/A)
                   → withRetry rethrows immediately
                   → persistedCount = 80 > 0 → download.pageFetchIncomplete(kept:80)
                   → break, return (count:80, wasPartial:true)
content phase: runs over the 80 persisted posts (each request paced + retried,
               best-effort) → completed climbs
run: emit .finished(postsFetched:80, warningMessage:"Downloaded 80 posts — some
     of the feed couldn't be reached.")

Zero-pages variant: page 1 permanent/exhausted, persistedCount = 0 → rethrow →
run catch → .failed("Could not download the feed.")  # unchanged
```

## Testing

Unit (`SpudDataKitTests`, Swift Testing; injected clock/sleep/jitter):

- `RequestPacer`:
  - Serial `acquire`s are spaced ≥ `minInterval` (assert the recorded sleep
    deadlines step by `minInterval`).
  - Concurrent `acquire`s (simulate the 4 workers) are serialized to
    `minInterval` apart, not all released at once.
  - `penalize(cooldown)` pushes the next `acquire`'s deadline out by `cooldown`;
    a later smaller `penalize` does not pull it back in.
- `withRetry`:
  - Transient-then-success: fails K < maxAttempts times then returns; asserts
    delays follow `base·2^(n-1)` (with a fixed jitter) capped at `maxDelay`.
  - Permanent: rethrows immediately, zero retries (assert operation called once).
  - Exhaustion: transient every time → rethrows the last error after exactly
    `maxAttempts` calls.
  - Pushback (503/429/rate_limit) calls `pacer.penalize`; a non-pushback transient
    (e.g. a plain timeout) retries WITHOUT penalize.
  - `CancellationError` is rethrown, not retried.
- `OfflineDownloadService` (fake `LemmyServiceType` scripted to fail K-then-succeed
  / fail-permanently; in-memory `AppDatabase`; injected clock so no real waiting):
  - Page fails transiently then succeeds → download completes with full count (no
    `.failed`), a `download.retry` diagnostic recorded.
  - Page fails permanently after ≥1 page → `.finished` with `warningMessage`
    non-nil; content phase ran over the kept posts; `download.pageFetchIncomplete`
    recorded.
  - First page fails permanently (zero posts) → `.failed` ("Could not download
    the feed."), unchanged.
  - Per-item comment fetch fails transiently then succeeds → item counts as a
    success (no `download.itemFailed`); fails permanently → swallowed +
    `download.itemFailed` (unchanged best-effort).

Extend the existing `OfflineDownloadServiceTests` fake rather than adding a new
one where possible. No snapshot tests (the only UI delta is a completion string,
covered by a value assertion on `warningMessage`).

## Files (anticipated)

New — `SpudDataKit/Services/Offline/`:
- `RequestPacer.swift`
- `RequestRetry.swift` (`withRetry` + the pushback predicate)

Modified — `SpudDataKit/Services/Offline/`:
- `OfflineDownloadService.swift` — tunable constants; build the per-run pacer;
  wrap `fetchFeed` in `fetchPages` (partial-outcome return + `wasPartial`);
  thread pacer/tunables into `processTarget` + `drainImageFetch`; carry
  `wasPartial` to the `.finished` terminal; new `download.retry` /
  `download.pageFetchIncomplete` diagnostics.
- `OfflineDownloadProgress.swift` — add `warningMessage: String?` (defaulted).

Modified — Spud app target (UI, thin):
- The offline-download progress/completion UI — surface `warningMessage` on
  `.finished` (locate the current sheet that renders the progress stream).

New — `SpudDataKitTests/`:
- `RequestPacerTests.swift`, `RequestRetryTests.swift`; extend
  `OfflineDownloadServiceTests.swift`.

Docs:
- `docs/features/offline-download.md` — retry / rate-limit / partial-success
  behavior + a Given/When/Then Scenario; README capability table + by-area map.

No migration.

## Open risks

- **`acquire` must sleep outside the actor.** If the sleep runs actor-isolated the
  pacer becomes a serial bottleneck (defeats the 4-way content concurrency).
  `reserve()` (sync bump) is the only isolated step; this is the unit-tested seam.
- **Cancellation vs retry.** `withRetry` must check cancellation before
  classifying, or a cancelled run's in-flight request could be misread as a
  transient failure and retried, delaying `.cancelled`. Covered by a test.
- **Partial vs empty boundary.** The keep-what-we-got path triggers only when
  `persistedCount > 0`; the first-page-fails case must still be `.failed`. The two
  service tests pin both sides.
- **Total back-off latency.** `maxAttempts=4` with the 30s cap and an 8s pushback
  cool-down means a persistently-pushing-back host can stretch a run; the page
  loop's own `maxPages` backstop and `maxPosts` cap still bound total work, and
  partial-success means the user still gets a usable feed rather than a spinner.
  Tunables are single constants, easy to dial.
