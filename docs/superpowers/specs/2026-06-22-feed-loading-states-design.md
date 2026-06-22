# Feed loading, error, and empty states — design

Date: 2026-06-22
Status: Approved (pending implementation plan)
Scope: Post list / feed loading first; the shared pieces are built to be reused by every screen that loads remote content.

## Problem

When a feed loads, the user sees an animated shimmer skeleton. Sometimes it
shimmers for a long time; sometimes it never resolves. The user cannot tell
which situation they are in:

- the network is just slow and they should wait,
- the request failed and they should retry,
- the internet is unavailable,
- or Spud hit a bug (e.g. couldn't parse the response).

The same ambiguity exists on every screen that loads remote content. This
design fixes the post list first and builds the classification + reachability
+ timeout logic as shared, reusable pieces.

## What exists today

- `FeedLoadingSkeletonView` — a shimmer skeleton shown on initial load
  (`PostListViewController.showLoadingSkeleton()` at
  `Spud/Scenes/PostList/PostListViewController.swift:693`), hidden on the first
  GRDB snapshot (`:744`).
- An error state already exists — `makeErrorConfiguration()`
  (`PostListViewController.swift:852`): a globe glyph, "Couldn't reach `<host>`",
  "Check your connection and try again.", with **Try again** / **Work offline**
  buttons. It only appears once the feed is empty *and* a fetch has thrown.
- A distinct empty state (`PostListViewModel.emptyState` at
  `PostListViewModel.swift:158`: "No posts" / "No saved posts yet").
- Initial-load state is modeled with three separate fields on
  `PostListViewModel` — `isFetchingNextPage`, `fetchFailed`, `lastFetchError`
  (`PostListViewModel.swift:39-48`) — which the controller reads in three
  separate observation tasks plus `hasReceivedFirstSnapshot`.

### Gaps that produce the symptoms

1. **No timeout tuning.** Lemmy API calls use `URLSession` defaults (60s
   request, *7-day* resource). A slow or half-open connection shimmers for up to
   a minute, or effectively forever — the "never completes" case.
2. **No connectivity awareness.** No `NWPathMonitor`. "You're offline" cannot be
   distinguished from "server down" or "just slow" — all look like a long
   shimmer.
3. **One generic error message** regardless of cause. Network failure, HTTP 5xx,
   auth problems, and parse/decode failures all render the same "Couldn't reach"
   text, so a Spud bug is indistinguishable from a slow network.
4. **Pagination failures are silent.** `AlertService.handle(_:for:)` only logs
   (`SpudDataKit/Services/Alert/AlertService.swift:31`); scrolling to load more
   and failing shows the user nothing
   (`PostListViewController.swift:443`).

## Decisions (anchors)

1. **Full failure taxonomy** — distinguish three failure causes: Offline /
   Can't reach server / Something went wrong in Spud (malformed response).
2. **Escalating shimmer + hard cap** — shimmer first; a "slow connection" hint
   after a threshold; a hard timeout that forces a result. No automatic retry.
3. **Shared logic, per-screen views** — classification, reachability, and
   timeout live in SpudDataKit / shared layers as pure, testable units. Each
   screen keeps its own view. Post list adopts them now; other screens later.

## Architecture

### Shared components (SpudDataKit)

**`LoadFailure`** — the classified cause, narrowed to exactly the three
presentation buckets, plus diagnostics for logging and the "copy details"
action.

```swift
public struct LoadFailure: Error, Equatable {
    public enum Kind: Equatable { case offline, unreachable, malformedResponse }
    public let kind: Kind
    public let diagnostics: String   // underlying error / HTTP status

    public static func classify(_ error: Error, isOnline: Bool) -> LoadFailure
}
```

`classify` rules:

- `isOnline == false` → `.offline` (takes precedence over the error inspection).
- `URLError.notConnectedToInternet`, `.dataNotAllowed` → `.offline`.
- `URLError.timedOut`, `.cannotConnectToHost`, `.cannotFindHost`,
  `.networkConnectionLost`, `.dnsLookupFailed`, `.secureConnectionFailed` →
  `.unreachable`.
- `LemmyServiceError.apiError(...)` carrying an HTTP 5xx (or a transport-level
  failure) → `.unreachable`.
- `DecodingError` (and any "we got bytes but couldn't read them" error) →
  `.malformedResponse`.
- Synthetic hard-cap timeout (see below) → `.unreachable` (or `.offline` if the
  monitor reports offline at that moment).
- Anything unclassified → `.unreachable` (conservative; never silently swallow).

`diagnostics` is a short human-readable string (error domain/code, HTTP status,
decoding context) used for `logger.error` and the malformed-state "copy
details" action. It is never shown verbatim in primary UI copy.

> Auth (`LemmyServiceError.requiresAuthentication`, HTTP 401/403) is out of
> scope for this iteration: signed-out browsing is normal in Spud and the three
> chosen buckets don't include it. For now it classifies as `.unreachable`.
> A dedicated "sign in again" state is a noted future refinement.

**`ReachabilityMonitoring`** — a protocol so view models can inject a fake.

```swift
public protocol ReachabilityMonitoring: Sendable {
    var isOnline: Bool { get }
    var statusStream: AsyncStream<Bool> { get }
}
```

Concrete implementation wraps `NWPathMonitor` (Network framework) on a private
queue, publishing changes through the shared `Broadcaster`/`AsyncStream` pattern
already used by `@UserDefaultsBacked`. Registered as a shared dependency
(`HasReachabilityMonitor`-style accessor) alongside the other SpudDataKit
services.

### Timeout enforcement (app-side, no LemmyKit change)

LemmyKit owns its own `URLSession`, and per the project CLAUDE.md a LemmyKit
edit does not reach Spud without a release + `exactVersion:` pin bump. So the
hard cap is enforced **app-side**: a structured-concurrency `withTimeout` helper
races the `fetchFeed` call against `Task.sleep(for: cap)`. On expiry it cancels
the fetch task and throws a synthetic timeout error, which `classify` maps to
`.unreachable` (or `.offline`). This keeps the whole fix inside the Spud repo.

Thresholds (injectable for tests; default constants in one place):

- **slow-hint**: ~8s — flip the loading state to `slow`.
- **hard cap**: ~25s — force a failure.

### View layer (Spud app target)

**`FeedLoadState`** replaces the `isFetchingNextPage` / `fetchFailed` /
`lastFetchError` triple for the *initial* load:

```swift
enum FeedLoadState: Equatable {
    case loading(slow: Bool)   // slow == true after the escalation threshold
    case loaded                // rows > 0
    case empty                 // fetch succeeded, zero rows
    case failed(LoadFailure)
}
```

`PostListViewModel` exposes a single `loadState: FeedLoadState`. The controller's
skeleton show/hide and `updateContentUnavailableState()` read *only* from this
enum, collapsing today's split-brain across `showLoadingSkeleton()`,
`hasReceivedFirstSnapshot`, `fetchFailed`, and `isFetchingNextPage`.

**`FeedStatePresenter`** (app / UIKit layer) maps `LoadFailure.Kind` + context
(host) → `(symbol, title, message, primaryAction, secondaryAction)`, producing
the `UIContentUnavailableConfiguration`. Other screens reuse it for identical
copy and behavior.

## Data flow & timing

"Loaded" is observed from GRDB, not from the fetch return, so two signals drive
the enum:

- **The fetch task** owns `.loading(slow:)` and `.failed`. On start it launches
  two timers: the slow-hint (flip to `loading(slow: true)` if still loading) and
  the hard cap (cancel + synthesize timeout). On `catch`, it calls
  `LoadFailure.classify(error, isOnline: monitor.isOnline)` → `.failed(kind)`.
- **The GRDB first snapshot** owns `.loaded` (rows > 0) vs `.empty` (rows == 0).

Lifecycle for the initial load (`feedChanged()` →):

1. `loadState = .loading(slow: false)`; show skeleton; start fetch + both timers.
2. slow-hint fires → `loadState = .loading(slow: true)` (skeleton stays, caption
   appears).
3. Resolution:
   - fetch succeeds and GRDB emits rows > 0 → `.loaded` (hide skeleton, show
     list).
   - fetch succeeds and GRDB emits rows == 0 → `.empty`.
   - fetch throws (or hard cap fires) → `.failed(kind)` (hide skeleton, show the
     content-unavailable state).
4. Reachability: while sitting in `.failed(.offline)`, a transition to online on
   `statusStream` triggers an automatic retry. (Other failure kinds require a
   manual **Try again**.)

The lazy feed-row creation path (`feedChanged()` awaiting the first
`fetchNextPage` when `feedRowIdSync` is nil,
`PostListViewController.swift:729`) is preserved; only the state bookkeeping
changes.

## Pagination failures

A separate, small state — `paginationState: .idle | .loading | .failed` —
independent of `FeedLoadState`, because posts stay visible. The existing
`.loading` footer section renders one of:

- **loading** → the current spinner (`LoadingFooterCell`, unchanged), or
- **failed** → "Couldn't load more — Retry", tap → `fetchNextPage()`.

This replaces the silent `alertService.handle(error, for: .fetchPostList)` at
`PostListViewController.swift:443`. Pagination reuses `classify` for diagnostics
(logging) but always shows the generic "Couldn't load more" copy — the
full-screen taxonomy is overkill for a footer.

## Copy & actions

| State | Symbol | Title | Message | Actions |
|---|---|---|---|---|
| Offline | `wifi.slash` | "You're offline" | "Spud will retry automatically when you're back online." | **Try again** (auto-retries on reconnect) |
| Can't reach server | `globe` | "Couldn't reach `<host>`" | "The server may be down or your connection is unstable." | **Try again** · Work offline |
| Something went wrong | `exclamationmark.triangle` | "Something went wrong" | "Spud couldn't read the response from `<host>`. This might be a bug." | **Try again** · Copy details |
| Slow (loading) | — | — | inline caption on the skeleton: "Still loading… slow connection" | — |
| Empty (unchanged) | `tray` / `bookmark` | "No posts" / "No saved posts yet" | existing copy | — |

All strings via `NSLocalizedString`. `<host>` comes from
`PostListViewModel.instanceHost` (`PostListViewModel.swift:141`).

**Open copy decision (for spec review):** the malformed/"Spud bug" case uses a
**Copy details** action (copies `diagnostics` to the clipboard). Spud is not
public yet (CLAUDE.md defers CONTRIBUTING "only if the project goes public"), so
a clipboard hook is the YAGNI-right amount; it can be swapped for a GitHub/email
report flow later.

## Testing

- **`LoadFailure.classify`** — pure unit tests in `SpudDataKitTests`: each
  `URLError` code, `LemmyServiceError.apiError` with 5xx, `DecodingError`, the
  synthetic timeout, and the `isOnline == false` override. No I/O.
- **`FeedLoadState` transitions** — `PostListViewModel` tests with a fake
  `LemmyService` (throws specific errors), a fake `ReachabilityMonitoring`, and
  **injectable slow/cap thresholds** (so tests don't wait 8s/25s). Covers:
  success→loaded, success-empty→empty, throw→failed(kind) per kind, slow-hint
  fires, hard-cap fires, reconnect auto-retry, pagination failure → footer
  retry → success.
- **`ReachabilityMonitoring`** behind the protocol; the `NWPathMonitor` concrete
  impl is verified manually, view models test against the fake.
- **Snapshot tests** — one reference per content-unavailable state (offline /
  unreachable / malformed / empty / slow-caption), following the iPhone 14 Pro
  portrait + git-annex re-record procedure in CLAUDE.md.

## Reuse path (other screens, later)

`LoadFailure`, `ReachabilityMonitoring`, the `withTimeout` helper, and
`FeedStatePresenter` are screen-agnostic. A future screen adopts the pattern by:
adding a `FeedLoadState`-equivalent to its view model, calling `classify` in its
`catch`, and rendering via `FeedStatePresenter`. No generic container view is
built now (YAGNI — deferred until a second screen's needs are concrete).

## Out of scope

- A dedicated auth / "sign in again" failure state.
- A full bug-report flow (GitHub/email) for the malformed case.
- Automatic retry with backoff for non-offline failures.
- A generic reusable content-state container view.
- Pull-to-refresh changes (unless the implementation surfaces a natural seam).
