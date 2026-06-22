# Post detail — comment loading skeleton + empty state — design spec

Date: 2026-06-22
Status: proposed (awaiting review)
Repo: `Spud/` (iOS app)

## Goal

When the post-detail content screen opens, the post header renders immediately
but the comments area below it sits blank while the comment fetch is in flight —
the screen reads as broken until comments pop in. Give that area a loading
state: a comment-shaped skeleton placeholder while comments load, and a
"No comments yet" empty state when a post genuinely has none.

## Scope

In scope:

- A comment-shaped **skeleton placeholder** shown in the comments region while a
  (non-pull-refresh) comment fetch is in flight and no comments are shown yet.
- A **"No comments yet" empty state** shown when the fetch settles with zero
  comments.
- An observable loading flag on `PostDetailViewModel`, driven by its
  `fetchComments()` network call.
- Reuse of the existing background-view loading idiom (`FeedLoadingSkeletonView`
  pattern), so no diffable-data-source changes.

Out of scope (explicit non-goals):

- Pull-to-refresh feedback — already covered by the existing `UIRefreshControl`;
  this change must not double up on it.
- The post header's own image-loading spinner (`PostDetailHeaderCell`) — unchanged.
- A live per-post comment **sort switcher** — not wired today
  (`didChangeCommentSortType` has no caller; sort is only a global preference).
  The loading flag is driven off the fetch so it covers that path the moment it
  is built, but no sort UI is added here.
- Skeleton rendered *over* already-loaded comments on a re-fetch (see
  "Approach" — rejected; the background-view skeleton intentionally stays behind
  existing comments).
- Error state for a failed comment fetch (already handled by
  `alertService.handle(error, for: .fetchComments)`); no new error UI here.

## Current state (grounding)

All file references are in `Spud/` unless noted.

- **Content screen:** `Scenes/PostDetail/Content/PostDetailViewController.swift` —
  a `UITableViewDiffableDataSource<Section, Item>` with two sections: `.header`
  (always present) and `.comments`. The header cell is opaque (`Theme.background`),
  so a `tableView.backgroundView` is occluded by it and is visible only in the
  blank region below — i.e. the comments area.
- **Fetch lifecycle:** `startObservations()` starts the header + comment GRDB
  observations, then the first comment snapshot calls
  `viewModel.didPrepareObservation(...)` which fires `viewModel.fetchComments()`.
  When the post is not yet mirrored, `startObservations()` early-returns after
  calling `didPrepareObservation(numberOfFetchedComments: 0)` (so the fetch still
  runs, but the comment observation is not started on that pass).
- **Pull-to-refresh:** `refreshControl` -> `reloadData()` -> `reloadAsync()` calls
  `viewModel.accountScope.lemmyService.fetchComments(...)` **directly**, bypassing
  `viewModel.fetchComments()`. Gating the loading flag inside
  `viewModel.fetchComments()` therefore excludes pull-to-refresh automatically.
- **View model:** `Scenes/PostDetail/Content/PostDetailViewModel.swift` —
  `@MainActor @Observable`. `fetchComments()` is `async`, currently sets no
  loading state. `orderedComments` exposes the current tree (empty when none).
- **Existing loading idiom (the model to mirror):**
  `Scenes/PostList/FeedLoadingSkeletonView.swift` is a pulsing skeleton set as
  `tableView.backgroundView` by `PostListViewController.showLoadingSkeleton()` /
  `hideLoadingSkeleton()` during the initial feed fetch (removed on first snapshot
  or failure). Reduce-motion aware; `isUserInteractionEnabled = false`.
- **Reactive helper:** `Utils/Extensions/Observation+AsyncStream.swift` —
  `ObservationStream.values(of:)` bridges an `@Observable` property read into an
  `AsyncStream`, yielding the initial value then re-yielding on change. This is
  the project-standard way to bind a view model property into a view controller
  (no hand-rolled `withObservationTracking` loops).
- **Empty-state precedent:** `PostListViewController` uses
  `UIContentUnavailableConfiguration` for its "No posts" state. That API overlays
  the whole VC view, which on post-detail would cover the header — so it is *not*
  reused here; a background view (occluded by the header) is used instead.

## Approach

The skeleton and the empty state are both rendered as `tableView.backgroundView`,
the same mechanism the feed uses. Because the header cell is opaque, the
background view is occluded by the header and shows only in the blank comments
region below it.

Consequence (accepted): a background view cannot paint *over* opaque comment
cells. So when a re-fetch happens while comments are already on screen (the
future sort-switch path), the skeleton stays hidden behind them and the comments
are simply replaced when the new set arrives — no flash over loaded content. This
honors "driven by the fetch, excludes pull-refresh" while avoiding a jarring
re-skeleton of content the user is already reading. Rendering the skeleton as
real rows that replace comments on every fetch was considered and rejected as
more invasive (diffable-data-source churn) for a path that does not exist yet.

## Components

### 1. `CommentLoadingSkeletonView` (new)

`Scenes/PostDetail/Content/Comment/CommentLoadingSkeletonView.swift`

A `UIView` analogue of `FeedLoadingSkeletonView`, shaped like comments rather
than feed rows:

- A vertical stack of ~6 skeleton rows. Each row: a small circular avatar bar
  (~24pt) and a short "name" bar on the first line, then 2–3 text bars of
  decreasing width.
- Rows carry **varying leading indentation** (e.g. depths 0,0,1,2,0,1) to read
  as a threaded tree, using the same depth-rail spacing constants as real
  comments where reasonable.
- Bars use `.tertiarySystemFill`, continuous-corner rounding (matching
  `FeedLoadingSkeletonView.bar`).
- `startAnimating()` / `stopAnimating()`: the same opacity pulse
  (`CABasicAnimation`, `0.8s`, autoreverse, infinite), **skipped under Reduce
  Motion** (bars stay static).
- `isUserInteractionEnabled = false`; `accessibilityElementsHidden = true`
  (decorative — VoiceOver should not land on it).

### 2. `PostDetailEmptyCommentsView` (new)

`Scenes/PostDetail/Content/Comment/PostDetailEmptyCommentsView.swift`

A small `UIView` for the settled-empty state, centered in its bounds:

- An SF Symbol (`text.bubble`) in `.tertiaryLabel`, a primary "No comments yet"
  label, and a secondary line (e.g. "Be the first to comment.").
- One accessibility element combining the two lines into a single label; not
  interactive.
- Plain background view (not `contentUnavailableConfiguration`) so it sits below
  the header rather than overlaying it.

### 3. `PostDetailViewModel` changes

- Add `private(set) var isLoadingComments: Bool = false` (observable; the
  `@Observable` macro tracks it).
- In `fetchComments()`, set the flag around the network call:

  ```swift
  func fetchComments() async {
      isLoadingComments = true
      defer { isLoadingComments = false }
      do {
          try await accountScope.lemmyService
              .fetchComments(serverPostId: serverPostId, sortType: commentSortType)
      } catch {
          alertService.handle(error, for: .fetchComments)
      }
  }
  ```

  This flips true for the initial fetch (via `didPrepareObservation`) and for the
  sort path (via `didChangeCommentSortType`) when it exists, and stays false for
  pull-to-refresh (which never calls this method).

### 4. `CommentsBackground` decision (new, pure)

`Scenes/PostDetail/Content/Comment/CommentsBackgroundState.swift`

The branching logic is the only genuinely bug-prone part, so it is extracted
from the view controller into a pure, unit-testable function:

```swift
enum CommentsBackground: Equatable {
    case skeleton   // loading, or initial pre-fetch — no comments on screen
    case empty      // a fetch has completed and the post has no comments
    case hidden     // comments are present (background view removed)

    static func decide(
        isLoadingComments: Bool,
        hasCompletedFetch: Bool,
        hasComments: Bool
    ) -> CommentsBackground {
        if hasComments { return .hidden }
        if isLoadingComments { return .skeleton }
        if hasCompletedFetch { return .empty }
        return .skeleton
    }
}
```

Key point — the empty state is gated on **`hasCompletedFetch`, not "first
snapshot received."** A fresh open emits an empty *cached* snapshot before the
network fetch begins; gating on first-snapshot would flash "No comments yet" for
that frame before the skeleton appears. Defaulting the initial state to
`.skeleton` and only switching to `.empty` once a fetch has actually completed
avoids the flash.

### 5. `PostDetailViewController` changes

- Replace the comment observation's local `hasReceivedFirstSnapshot` (which only
  gated the one-time `didPrepareObservation` call) with two instance properties,
  both reset to `false` at the top of `startObservations()`:
  - `hasReceivedFirstCommentSnapshot` — still gates the single
    `didPrepareObservation(numberOfFetchedComments:)` call;
  - `hasCompletedCommentFetch` — set `true` when `isLoadingComments` transitions
    `true -> false` (detected in the loading-observation task below).
- Hold lazily-created `commentLoadingSkeletonView` and `emptyCommentsView`, plus
  `loadingObservationTask`.
- `updateCommentsBackground()` maps `CommentsBackground.decide(...)` onto the
  table's background view and drives the pulse, guarding against redundant
  assignment (mirrors `showLoadingSkeleton`'s `backgroundView !== ...` check):

  ```
  switch CommentsBackground.decide(
      isLoadingComments: viewModel.isLoadingComments,
      hasCompletedFetch: hasCompletedCommentFetch,
      hasComments: !viewModel.orderedComments.isEmpty
  ) {
  case .skeleton: backgroundView = skeleton (if not already); skeleton.startAnimating()
  case .empty:    skeleton.stopAnimating(); backgroundView = emptyCommentsView (if not already)
  case .hidden:   skeleton.stopAnimating(); backgroundView = nil (if not already)
  }
  ```

- Drive it from:
  - a new `loadingObservationTask`,
    `ObservationStream.values(of: { viewModel.isLoadingComments })`, that detects
    the `true -> false` edge (sets `hasCompletedCommentFetch`) and calls
    `updateCommentsBackground()` on each yield. Started in `startObservations()`,
    cancelled/restarted on `setPost`, cancelled in `deinit`. The access closure
    reads through `[weak self]` to avoid a retain cycle and to always see the
    live (post-`setPost`) view model;
  - the end of `applySnapshot()` (after `orderedComments` updates), so arriving
    or vanishing comments re-evaluate the background.

## Edge cases

- **Revisit with cached comments:** the comment observation emits cached rows
  immediately; `orderedComments` is non-empty, so `decide` returns `.hidden` even
  while a background refetch runs. No skeleton flash.
- **Fresh open, empty cache:** the first (empty) cached snapshot arrives before
  the fetch starts — `decide` returns `.skeleton` (loading not yet true, fetch
  not yet completed), so no "No comments yet" flash; the fetch then keeps it on
  `.skeleton`.
- **Genuinely 0-comment post:** skeleton shows during the fetch; when
  `isLoadingComments` goes `true -> false` with no comments,
  `hasCompletedCommentFetch` is set and `decide` returns `.empty`.
- **Post not yet mirrored** (`startObservations` early-return branch): the fetch
  still runs and `hasCompletedCommentFetch` is set on completion; with no
  comments mirrored this lands on `.empty` ("No comments yet"). This matches the
  pre-existing limitation that this branch does not bring comments in until the
  screen is re-entered, and is an acceptable resting state.
- **Reduce Motion:** skeleton bars render static (no pulse).
- **Tall header filling the viewport:** the skeleton is fully occluded until the
  user scrolls; acceptable (nothing to show in zero blank space).

## Testing

- **Unit tests** (SpudTests) for `CommentsBackground.decide(...)` — the full
  8-row truth table over the three boolean inputs — and for
  `PostDetailViewModel.isLoadingComments` defaulting to `false`. The live
  `true/false` toggle around the network call is left to manual verification (it
  is fetch-timing dependent and there is no `LemmyService` mock in SpudTests);
  the `isLoading == true` branch is exercised by the decision-function tests.
- **Snapshot tests** (SpudSnapshotTests, iPhone 14 Pro / portrait plan) for
  `CommentLoadingSkeletonView` and `PostDetailEmptyCommentsView` rendered at a
  fixed size, matching the existing PostDetail snapshot coverage. Record refs one
  class at a time and follow the git-annex re-record dance documented in
  `Spud/CLAUDE.md` (never `git annex restage` between record and verify; commit
  new refs before any branch switch).
- **Manual on-sim verification** of the live transitions, since they are
  fetch-timing dependent:
  - fresh open of a post with no cached comments -> skeleton -> comments;
  - open of a 0-comment post -> skeleton -> "No comments yet";
  - pull-to-refresh shows only the refresh control (no skeleton);
  - revisit of a cached post shows comments immediately (no skeleton).

## Build / project notes

- Two new source files under `Scenes/PostDetail/Content/Comment/` require
  `make project` (XcodeGen) before they compile into the target.
- No new dependencies, no GRDB schema/migration changes.
