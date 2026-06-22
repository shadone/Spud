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

### 4. `PostDetailViewController` changes

- Promote the comment observation's local `hasReceivedFirstSnapshot` to an
  instance property `hasReceivedFirstCommentSnapshot`, set when the first comment
  snapshot arrives in `startCommentObservation`, reset to `false` in
  `setPost(...)` / at the top of `startObservations()`.
- Hold lazily-created `commentLoadingSkeletonView` and `emptyCommentsView`.
- `updateCommentsBackground()` selects the background view and drives the pulse:

  ```
  let isEmpty = viewModel.orderedComments.isEmpty
  if viewModel.isLoadingComments && isEmpty:
      backgroundView = skeleton; skeleton.startAnimating()
  else if hasReceivedFirstCommentSnapshot && !viewModel.isLoadingComments && isEmpty:
      backgroundView = emptyCommentsView
  else:
      skeleton.stopAnimating(); backgroundView = nil
  ```

  Guards against redundant assignment (mirrors `showLoadingSkeleton`'s
  `backgroundView !== ...` check) so it can be called freely.
- Drive it from:
  - a new observation task,
    `ObservationStream.values(of: { viewModel.isLoadingComments })`, that calls
    `updateCommentsBackground()` on each yield (started in `startObservations()`,
    cancelled/restarted on `setPost`, cancelled in `deinit`);
  - the end of `applySnapshot()` (after `orderedComments` updates), so arriving
    or vanishing comments re-evaluate the background.

## Edge cases

- **Revisit with cached comments:** the comment observation emits cached rows
  immediately; `orderedComments` is non-empty, so the background is `nil` even
  while a background refetch runs. No skeleton flash.
- **Genuinely 0-comment post:** skeleton shows during the fetch; on settle,
  `hasReceivedFirstCommentSnapshot` is true and `orderedComments` is empty, so the
  empty state shows.
- **Post not yet mirrored** (`startObservations` early-return branch): the fetch
  runs (skeleton shows while empty), but the comment observation has not started,
  so `hasReceivedFirstCommentSnapshot` stays false — the empty state is correctly
  suppressed (background falls to `nil` after the fetch) rather than flashing
  "No comments yet" before the first snapshot.
- **Reduce Motion:** skeleton bars render static (no pulse).
- **Tall header filling the viewport:** the skeleton is fully occluded until the
  user scrolls; acceptable (nothing to show in zero blank space).

## Testing

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
