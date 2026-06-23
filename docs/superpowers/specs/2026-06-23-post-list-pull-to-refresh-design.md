# Post list pull-to-refresh — design

Date: 2026-06-23
Status: Approved (pending implementation plan)
Scope: `PostListViewController` only. No view-model or data-layer changes.

## Problem

The post list has no way to manually refresh the feed. The user can only get
fresh content by leaving and re-entering the feed, changing the sort, or
triggering one of the implicit reloads (block a user/community, reconnect after
offline). The standard iOS gesture — pull down to refresh — is missing.

## What exists today

- **No `UIRefreshControl`** anywhere in the post list. The convention is already
  established elsewhere in the app: `InboxViewController`, `PersonViewController`,
  and `PostDetailViewController` each own a `UIRefreshControl` and call
  `endRefreshing()` when their load settles.
- **A fresh-feed reload path already exists.** `PostListViewModel.didClickReload()`
  (`PostListViewModel.swift:110`) mints a brand-new feed key
  (`accountService.createFeed(duplicateOf:...)`) and resets pagination via
  `resetForNewFeed()` (`:120`), driving `loadState` to `.loading`. The controller's
  `reloadFeed()` (`PostListViewController.swift:672`) wraps it as
  `didClickReload()` + `feedChanged()`. This is the correct refresh semantic for a
  cursor-paginated Lemmy feed: re-pull from the top.
- **`feedChanged()`** (`PostListViewController.swift:708`) tears down the current
  observation, clears `rowsByServerPostId` / `orderedRows` / `displayedRows`,
  shows the full-screen `FeedLoadingSkeletonView`, then awaits `loadFirstPage()`
  for the new feed key and starts a GRDB observation that swaps in the new rows on
  the first snapshot (`apply(rows:animatingDifferences: false)`).
- **`applyLoadState(_:)`** (`PostListViewController.swift:814`) renders the
  load-state surfaces: skeleton on `.loading`, the designed empty state on
  `.empty`, and the `makeErrorConfiguration()` error surface (retry / work offline)
  on `.failed`.
- **`ToastPresenter.shared.show(_:in:)`** (`Spud/Scenes/Common/Toast/ToastPresenter.swift`)
  — a transient, non-blocking pill toast, recently added and used for vote/save/hide
  failures. Takes a `UIWindow`.

### The wrinkle

`feedChanged()` always clears the list and shows the skeleton. Wiring the refresh
control straight to `reloadFeed()` would momentarily blank the feed on every pull,
which feels heavier than a standard pull-to-refresh. The decision below keeps the
existing posts on screen while the new feed loads.

## Decisions

1. **Refresh = fresh feed key.** Pull-to-refresh reuses `viewModel.didClickReload()`
   (new feed key, reset pagination) — the same semantic as the existing
   `reloadFeed()`. Re-pulls from the top of the feed.
2. **Keep posts on screen; the control is the only progress indicator.** Mirror the
   `InboxViewController` convention: suppress the in-place loading surface
   (skeleton) while `refreshControl.isRefreshing`, and `endRefreshing()` when the
   load settles. Existing posts stay visible until the new feed's first GRDB
   snapshot swaps them in via the existing `apply(rows:)`.
3. **Failed refresh keeps posts + toast.** If a pull-to-refresh fails *while posts
   are on screen*, keep the old posts and surface the failure as a transient toast
   instead of replacing the list with the full error surface. Consistent with the
   project's vote/save/hide failure toasts. A failed refresh with no existing
   content — and every normal initial-load failure — still shows the full error
   surface with retry, unchanged.
4. **All feed types.** Frontpage, community, and saved feeds share this controller,
   so all get pull-to-refresh. (Pulling the saved feed re-fetches saved posts.)

## Changes (all in `PostListViewController.swift`)

1. **`refreshControl`** — new `private lazy var refreshControl: UIRefreshControl`,
   target `#selector(refreshTriggered)` on `.valueChanged`. Attach with
   `tableView.refreshControl = refreshControl` in `viewDidLoad()`.

2. **`@objc private func refreshTriggered()`** —
   ```swift
   viewModel.didClickReload()        // fresh feed key + pagination reset
   feedChanged(keepingContent: true) // keep posts, no skeleton
   ```

3. **`feedChanged(keepingContent: Bool = false)`** — add the parameter. Existing
   callers pass nothing (`false`) and are unchanged. When `true`:
   - **Skip** clearing `rowsByServerPostId` / `orderedRows` / `displayedRows`
     (posts stay visible).
   - **Skip** `showLoadingSkeleton()`.
   - Still reset `pinnedReadIds` / `markedReadIds` (they belong to the prior feed
     session; the new first snapshot re-pins) and set
     `hasReceivedFirstSnapshot = false` so the new feed's first snapshot is treated
     as first (re-pin, resolve, swap).
   - The observation task is unchanged: it awaits `loadFirstPage()` for the new
     key, then the first snapshot calls `apply(rows:animatingDifferences: false)`,
     replacing the old posts with the fresh ones in one step.
   - In the early-return "feed row never materialized" failure branch
     (`PostListViewController.swift:732`), when `keepingContent` is true, do not
     touch content — `applyLoadState(.failed)` handles ending the spinner and the
     toast (see below).

4. **`applyLoadState(_:)`** — two edits mirroring `InboxViewController.render()`:
   - `.loading`: only `showLoadingSkeleton()` (+ slow hint) when
     `!refreshControl.isRefreshing`. Always clear `contentUnavailableConfiguration`.
   - `.loaded`: `refreshControl.endRefreshing()`, then hide skeleton + clear
     surface as today.
   - `.empty`: `refreshControl.endRefreshing()`, then show the empty surface as
     today. (A refresh that legitimately returns zero posts has already cleared the
     list via `apply(rows: [])`, so the empty state is correct.)
   - `.failed`:
     ```swift
     if refreshControl.isRefreshing, !displayedRows.isEmpty {
         refreshControl.endRefreshing()
         showRefreshFailureToast(for: failure)   // keep old posts
     } else {
         refreshControl.endRefreshing()
         hideLoadingSkeleton()
         contentUnavailableConfiguration = makeErrorConfiguration(for: failure)
     }
     ```

5. **`showRefreshFailureToast(for:)`** — new helper:
   ```swift
   guard let window = view.window else { return }
   let message = failure.kind == .offline
       ? NSLocalizedString("You're offline", comment: "Toast when pull-to-refresh fails while offline")
       : NSLocalizedString("Couldn't refresh", comment: "Toast when pull-to-refresh fails")
   ToastPresenter.shared.show(message, in: window)
   ```

## Data flow

```
pull ──▶ refreshTriggered()
        ├─ viewModel.didClickReload()         (new feed key, loadState = .loading)
        └─ feedChanged(keepingContent: true)  (posts kept, no skeleton)
                │
                ├─ applyLoadState(.loading): isRefreshing ⇒ no skeleton, posts stay
                │
                ├─ await loadFirstPage(newKey)
                │     success ─▶ GRDB first snapshot ─▶ apply(rows: fresh) swaps list
                │                resolveInitialSnapshot ─▶ loadState = .loaded/.empty
                │                applyLoadState ─▶ endRefreshing()
                │
                └─ failure ─▶ loadState = .failed
                              applyLoadState(.failed):
                                isRefreshing && posts on screen
                                  ⇒ endRefreshing() + toast, keep posts
                                else ⇒ endRefreshing() + full error surface
```

## Edge cases

- **Empty after refresh** — `apply(rows: [])` clears the list, `.empty` surface
  shows. Correct: content genuinely went away (e.g. unsaved everything on the saved
  feed).
- **Failed refresh, no prior content** — falls through to the full error surface
  with retry (the `!displayedRows.isEmpty` guard). Same as a normal failed load.
- **Offline auto-retry on reconnect** (`reachabilityObservationTask`,
  `PostListViewController.swift:439`) still calls the normal `feedChanged()`
  (skeleton) path — unchanged.
- **Rapid re-pull** — each pull cancels the prior observation task and starts a
  new one, the same as the existing reload paths. No extra guard needed.

## Testing

This is UIKit glue that reuses existing view-model methods; it adds no new
view-model logic to unit-test. Verification:

- **Build green** (`Spud` scheme).
- **Manual simulator check**: pull to refresh on a feed — posts stay, spinner
  shows, list swaps to fresh content, spinner ends. Pull while offline (airplane
  mode / Network Link Conditioner) — posts stay, "You're offline" toast appears,
  spinner ends.
- If an existing `PostListViewModel` unit test or PostList snapshot test is worth
  a small extension (e.g. asserting `didClickReload()` mints a new feed key), add
  it; otherwise rely on the build + manual check.

## Out of scope

- No automatic refresh-on-foreground or refresh-on-interval.
- No haptics beyond `UIRefreshControl`'s default.
- No changes to pagination, sort switching, or the offline auto-retry behavior.
