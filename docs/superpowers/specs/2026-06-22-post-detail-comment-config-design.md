# Post detail — comment config (sort + density) — design spec

Date: 2026-06-22
Status: proposed (awaiting review)
Repo: `Spud/` (iOS app)

## Goal

Give the post-detail screen a config control — a `slider.horizontal.3` nav-bar
button beside the `•••` overflow, mirroring the post-list Quick Switch — that
opens a popover for **comment sort** (per-post) and **comment density**
(comfortable/compact). Along the way, make the comment fetch unit-testable (a
narrow injectable seam) and upgrade the fetch to cancel-and-replace so a sort
change supersedes an in-flight fetch.

## Scope

In scope:

- A new nav-bar **config button** (`slider.horizontal.3`) on the post-detail
  content screen, opening a SwiftUI popover (forced popover on iPhone).
- **Comment sort** selection in the popover (the 5 `CommentSortType` cases),
  applied **per-post** (the global `defaultCommentSortType` is untouched).
- **Comment density** (`comfortable`/`compact`) — a new preference, independent
  of the feed's `postDensity`, applied live to comment cells.
- **Cancel-and-replace** comment fetch (`PostDetailViewModel.fetchComments`),
  replacing the drop-second guard added previously, so a sort change supersedes
  an in-flight fetch with no flag flap and no spurious error on cancellation.
- A **testable fetch seam** (injected closure) so the loading flag and
  cancel-and-replace behaviour are unit-tested.
- Restarting the comment GRDB observation with the new sort on a sort change.

Out of scope (explicit non-goals):

- **Text size** in the popover — it stays on Settings → Display (the post-list
  Quick Switch deliberately excludes it too; one shared `postTextScale` drives
  all post-text surfaces).
- **Comment ribbon theme** in the popover — left where it is.
- Density on the **post header body** — comment density affects comment cells
  only; the header (the post itself) stays `.comfortable`.
- A **Settings → Display** row for comment density — popover-only for now (a
  Settings home can be added later if wanted).
- Persisting the chosen comment sort as the global default — per-post only.
- A standalone comment **sort button** (like the post list's separate sort
  button) — sort lives inside the config popover.

## Current state (grounding)

All file references are in `Spud/` unless noted.

- **Post-list Quick Switch (the pattern to mirror):**
  `Scenes/PostList/QuickSwitch/` — `QuickSwitchViewModel` (seeds prefs once,
  writes display prefs through `PreferencesService`, routes sort via an
  `onSelectSort` callback), `QuickSwitchView` (a `Form` of segmented pickers +
  a Sort `NavigationLink`), `QuickSwitchSortView` (the pushed sort picker).
  Presented from `PostListViewController.quickSwitchTapped()` via a
  `UIHostingController` with `.popover` + `ForcePopoverDelegate`
  (`Scenes/PostList/QuickSwitch/ForcePopoverDelegate.swift`) so it stays a
  popover on iPhone.
- **Comment fetch:** `Scenes/PostDetail/Content/PostDetailViewModel.swift` —
  `fetchComments()` currently sets `isLoadingComments`, guards re-entry
  (`guard !isLoadingComments`), and calls
  `accountScope.lemmyService.fetchComments(serverPostId:sortType:)`.
  `commentSortType` is a `var` seeded from
  `preferencesService.defaultCommentSortType`. `didChangeCommentSortType(_:)`
  exists but has **no caller** (dead).
- **Comment observation:** `Scenes/PostDetail/Content/PostDetailViewController.swift`
  — `startCommentObservation(postRowId:)` captures
  `sortTypeRaw = viewModel.commentSortType.rawValue` at start and observes
  `appDatabase.observePostDetailComments(postRowId:sortType:)`. There is already
  a preference-observation precedent in this VC:
  `startSwipeActionsObservation()` watches `preferencesService.commentSwipeActionsStream`
  and calls `reconfigureVisibleSwipeActions()`.
- **Comment cell body view:**
  `Scenes/PostDetail/Content/Comment/PostDetailCommentCell.swift` —
  `makeBodyView(textScale:)` builds a `MarkdownContext(kind: .comment,
  textScale:, density: .comfortable)` (density hardcoded). The cell tracks
  `bodyViewTextScale` and rebuilds the body view on `configure` when the scale
  changes (`bodyViewTextScale`, lines ~337-340). The header cell
  (`PostDetailHeaderCell.makeBodyView`) does the same for the post body.
- **Density model:** `SpudUIKit/Theme/PostDensity.swift` —
  `enum PostDensity { case comfortable, compact }` with `title`, `symbolName`,
  and `relativeFontSizeAdjustment` (fed into `MarkdownContext`'s baked fonts).
  The feed's `postDensity` preference drives feed cells; comments are unaffected
  today.
- **Appearance:** `Services/Appearance/PostDetail/PostDetailAppearance.swift` —
  `PostDetailAppearanceType` exposes `textSizeAdjustment` (forwards to
  `preferencesService.postTextScale`) and `commentRibbonTheme` (a
  `@UserDefaultsBacked`). The VC reads `appearanceService.postDetail` in the
  cell provider.
- **Loading state:** `CommentsBackground.decide(isLoadingComments:
  hasCompletedFetch:hasComments:)` (from the prior feature) returns `.hidden`
  whenever comments are present, so a re-sort over existing comments shows no
  skeleton.
- **Preferences:** `Services/Preferences/PreferencesService.swift` —
  `@UserDefaultsBacked` properties with an `AsyncStream` projected value;
  `*Stream` accessors forward `$prop`. `defaultCommentSortType` (`.Hot`) and
  `commentSwipeActions` follow this shape.
- **Sort titles:** `Utils/Extensions/CommentSortType+itemForMenu.swift` —
  `Components.Schemas.CommentSortType.itemForMenu.title` for Hot/Top/New/Old/
  Controversial.

## Components

### 1. `commentDensity` preference

`Services/Preferences/PreferencesService.swift`:

- Protocol: `var commentDensity: PostDensity { get set }` and
  `var commentDensityStream: AsyncStream<PostDensity> { get }`.
- Impl: `@UserDefaultsBacked(key: "commentDensity") var commentDensity:
  PostDensity = .comfortable`, with `commentDensityStream` forwarding
  `$commentDensity`.

`Services/Appearance/PostDetail/PostDetailAppearance.swift`:

- `PostDetailAppearanceType` gains `var commentDensity: PostDensity { get set }`
  and `var commentDensityStream: AsyncStream<PostDensity> { get }`, both
  forwarding to `preferencesService`. (Mirrors how `textSizeAdjustment` forwards
  to `postTextScale`.)

Independent of the feed's `postDensity` — changing comment density does not
affect the feed and vice versa.

### 2. Comment cell density

`Scenes/PostDetail/Content/Comment/PostDetailCommentCell.swift`:

- `makeBodyView(textScale:density:)` passes `density` into the `MarkdownContext`.
- Add `private var bodyViewDensity: PostDensity = .comfortable`; in `configure`,
  rebuild the body view when **either** `textScale` or `density` changed (extend
  the existing `bodyViewTextScale` compare).
- The cell reads the density from its view model
  (`PostDetailCommentViewModel`), which carries it from `appearance.postDetail.commentDensity`
  (set where the existing `appearance` is threaded into the cell provider). Keep
  the data flow identical to how `textScale` reaches the cell.

The header cell is unchanged (post body stays `.comfortable`).

### 3. Live density re-flow (VC)

`PostDetailViewController`:

- `startCommentDensityObservation()` — mirrors `startSwipeActionsObservation()`
  exactly: a `Task` doing `for await density in
  preferencesService.commentDensityStream` that, on a changed value, calls
  `reconfigureVisibleComments()` (a `snapshot.reconfigureItems(commentItems)`
  like `reconfigureVisibleSwipeActions`).
  Reconfigure re-runs the cell provider, which rebuilds body views whose density
  changed. Started in `viewDidLoad` (independent of the backing post, like the
  swipe-action observation); cancelled in `deinit`.

### 4. Testable fetch seam + cancel-and-replace

`PostDetailViewModel`:

- New init parameter
  `fetchCommentsOperation: ((Components.Schemas.CommentSortType) async throws -> Void)? = nil`,
  resolved once in init to a stored closure: the injected one, or a default
  `{ [accountScope, serverPostId] sortType in try await
  accountScope.lemmyService.fetchComments(serverPostId: serverPostId, sortType:
  sortType) }`. `accountScope` is retained for the VC's other calls.
- `commentSortType` becomes `private(set)`; add `func setCommentSortType(_:)`
  that assigns it. Remove the dead `didChangeCommentSortType`.
- `fetchComments()` becomes cancel-and-replace:

  ```
  fetchTask?.cancel()
  isLoadingComments = true
  let sortType = commentSortType
  let task = Task { @MainActor [weak self] in
      guard let self else { return }
      do {
          try await fetchCommentsOperation(sortType)
      } catch is CancellationError {
          // superseded — leave the flag to the winning fetch
      } catch {
          if !Task.isCancelled { alertService.handle(error, for: .fetchComments) }
      }
      if !Task.isCancelled { isLoadingComments = false }  // only the winner clears it
  }
  fetchTask = task
  await task.value
  ```

  `fetchTask` is `@ObservationIgnored private var`. A superseded fetch never
  clears the flag or shows an error, so the flag stays true across a
  cancel→restart with no flap, and cancellation is silent.

### 5. Sort change orchestration (VC)

`PostDetailViewController.changeCommentSort(to:)`:

```
guard sortType != viewModel.commentSortType else { return }
viewModel.setCommentSortType(sortType)
if let postRowId = appDatabase.postRowIdSync(forKeychainId:, serverPostId:) {
    startCommentObservation(postRowId: postRowId)   // re-reads the new sort
}
Task { await viewModel.fetchComments() }             // cancel-and-replace, new sort
```

`startCommentObservation` already cancels its prior task and reads
`viewModel.commentSortType`, so it restarts cleanly with the new sort. The first
emission is the cached comments in the new order; the fetch refreshes from the
network. `hasReceivedFirstCommentSnapshot` is already true, so the restart does
not re-fire `didPrepareObservation` (no double fetch). Comments stay visible
during the re-sort (no skeleton, per `CommentsBackground.decide`).

### 6. Config button + popover

`PostDetailViewController`:

- A `configBarButtonItem` (`slider.horizontal.3`), shown alongside
  `overflowBarButtonItem` via `navigationItem.rightBarButtonItems`. A retained
  `ForcePopoverDelegate` (reused from the post-list type).
- `configTapped()` builds a `PostDetailConfigViewModel` and presents
  `UIHostingController(rootView: PostDetailConfigView(...))` with
  `.modalPresentationStyle = .popover`, `sizingOptions = [.preferredContentSize]`,
  `popover.sourceItem = configBarButtonItem`, `popover.delegate = forcePopoverDelegate`.

`Scenes/PostDetail/Content/Config/` (new):

- `PostDetailConfigViewModel` (`@MainActor @Observable`) — mirrors
  `QuickSwitchViewModel`: seeds `commentDensity` from the appearance/prefs and
  `currentSort` from the VM; `updateCommentDensity(_:)` writes the pref (live
  re-flow); `selectSort(_:)` routes to an `onSelectSort` callback.
- `PostDetailConfigView` — a `Form` with a **Density** segmented `Picker`
  (`PostDensity.allCases`) and a **Sort** `NavigationLink` showing the current
  sort, pushing `PostDetailConfigSortView`.
- `PostDetailConfigSortView` — lists the 5 `CommentSortType` cases (via
  `itemForMenu.title`), checkmarks the current, applies on tap and pops.

The popover's `onSelectSort` is wired to `changeCommentSort(to:)` (Component 5).

## Edge cases

- **Sort change with no mirrored post row** (rare): the observation isn't
  restarted (guard), but `fetchComments()` still runs for the new sort; the
  observation picks up the new order on the next `startObservations`.
- **Rapid sort changes:** each `changeCommentSort` cancels the prior fetch
  (cancel-and-replace) and restarts the observation; the last one wins. The
  loading flag does not flap.
- **Density change while loading:** independent of the fetch; reconfigure only
  rebuilds body views, leaving the loading background logic alone.
- **Signed-out / fetch error:** unchanged — a genuine (non-cancellation) error
  still routes to `alertService.handle(_, for: .fetchComments)`.
- **Reduce Motion / Dynamic Type:** unaffected; density changes font size via
  the same baked-font path as text scale.

## Testing

- **Unit (SpudTests), enabled by the seam** — inject a controllable
  `fetchCommentsOperation`:
  - `isLoadingComments` is `true` while a fetch is in flight (operation held
    open on a continuation), `false` after it completes.
  - Cancel-and-replace: a second `fetchComments()` cancels the first (the first
    operation observes `Task.isCancelled`); the flag clears once, and no error
    is surfaced for the cancelled fetch.
  - A genuine error from the operation routes to the alert service and clears
    the flag.
  - `setCommentSortType` updates `commentSortType`.
- **Snapshot (SpudSnapshotTests, device-independent: pinned size +
  `displayScale: 2`):**
  - `PostDetailConfigView` popover content (light/dark).
  - A `PostDetailCommentCell` at `compact` density (light/dark), to lock the
    denser rendering.
  - Existing comment / skeleton / empty snapshots must not drift.
- **Manual (on-sim, tap automation unavailable here — user gate):** open the
  config popover; switch sort → comments reorder; toggle density → comments
  re-flow live; popover stays a popover on iPhone.

## Build / project notes

- New source files under `Scenes/PostDetail/Content/Config/` (and any new test
  files) require `make project` (XcodeGen).
- New `commentDensity` `@UserDefaultsBacked` key: `"commentDensity"`. No GRDB
  schema/migration change.
- No new third-party dependencies. `AlertService.Effect.fetchComments` already
  exists.
