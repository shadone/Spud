# Quick Switch — design spec

Date: 2026-06-18
Status: proposed (awaiting review)
Repo: `Spud/` (iOS app)

## Goal

Add a **Quick Switch** control to the post-list nav bar: a sliders button beside
Compose that opens a popover for customizing how the feed renders — density,
thumbnail position, vote-button visibility, and sort — without leaving the feed.

This is an *entry point* feature. Every preference it touches already exists, is
already persisted, and already re-flows the feed live. Quick Switch surfaces them
in one tap from the feed itself.

## Scope

In scope:

- A new nav-bar button (sliders icon) on every post-list screen.
- A popover hosting: Density, Thumbnail position, Vote buttons, and a Sort row.
- Reuse of the existing preference + sort-change machinery (no new persistence).
- A small refactor extracting the sort-menu grouping into a shared model so the
  existing `UIMenu` and the new SwiftUI sort list share one source of truth.

Out of scope (explicit non-goals for this change):

- The **Immersive** feed layout (full-bleed media cells). It does not exist and was
  previously deferred; the design's Compact↔Immersive toggle is therefore omitted.
- Accent color in the popover — it is app-wide theming, lives in Settings →
  Appearance, and is not feed-specific.
- Text-size slider in the popover (stays in Settings → Display).
- "Set sort as default for this feed" — a possible follow-up, not built here.

## Current state (grounding)

All file references are in `Spud/` unless noted.

- **Post list screen:** `Scenes/PostList/PostListViewController.swift` —
  UIKit `UIViewController` + `UITableView` with a diffable data source. View model is
  `@Observable PostListViewModel` (`Scenes/PostList/PostListViewModel.swift`).
- **Nav-bar trailing items** are owned by
  `PostListViewController.updateTrailingBarButtonItems()` (line ~279). Today:
  `[sortTypeBarButtonItem]`, or `[composeButton, sortTypeBarButtonItem]` on a
  frontpage feed (compose is frontpage-only).
- **Display preferences** live in `Services/Preferences/PreferencesService.swift`,
  UserDefaults-backed via `@UserDefaultsBacked`, each exposed both as a `var` and as
  an `AsyncStream` projected value (`postDensityStream`, etc.). Relevant prefs:
  - `postDensity: PostDensity` — `.comfortable` / `.compact`
  - `thumbnailPosition: ThumbnailPosition` — `.left` / `.right` / `.hidden`
  - `showVoteButtons: Bool`
  - (also `postTextScale`, `accentColor` — not used by Quick Switch)
  - Enums (`SpudUIKit/Theme/`) expose `.title` and `.symbolName` (and `AccentColor`
    `.color`). Used today by `Scenes/Preferences/PreferencesDisplayView.swift`.
- **Feed already re-flows on pref change:** `PostListViewController` observes
  `postDensityStream` (line ~449), `thumbnailPositionStream` (~461), and
  `showVoteButtonsStream` (~485); each calls `reconfigureVisibleCells()`
  (snapshot `reconfigureItems`). No new observation is required.
- **Sort:** the current sort lives in `viewModel.feed.feedType.sortType`. The sort
  menu is built in `setupSortTypeMenu()` (~577) / `rebuildSortTypeMenu(activeSortType:)`
  (~615) from three local groups — `actives`, `tops`, `comments`. A selection calls
  `sortTypeChanged(to:)` (~644), which does
  `viewModel.didChangeSortType(_:)` → `feedChanged()` → `rebuildSortTypeMenu(...)`.
  `SortType.itemForMenu` (`Utils/Extensions/SortType+itemForMenu.swift`) provides each
  sort's title + SF Symbol.
- **Unrelated:** `Scenes/MainWindow/QuickSwitch/FeedSwitcherViewController.swift`
  switches feed *type* (All / Local / Subscribed / Saved) via the left-edge swipe.
  Quick Switch switches feed *display*. Despite the folder name, they are distinct;
  this change does not touch the feed switcher.

## UX

**Button.** A `UIBarButtonItem` with SF Symbol `slider.horizontal.3`, placed by
`updateTrailingBarButtonItems()`:

- Frontpage feed: `[composeButton, quickSwitchButton, sortTypeBarButtonItem]`
  (compose remains right-most; Quick Switch sits immediately left of it).
- Community / saved feed (no compose): `[quickSwitchButton, sortTypeBarButtonItem]`.
- Shown on **every** post-list screen — density/thumbnail/sort all apply everywhere
  (unlike compose).

**Presentation.** A SwiftUI view in a `UIHostingController` presented as a `.popover`
anchored to the bar button (`popoverPresentationController.sourceItem`). On compact
width (iPhone) the adaptive presentation delegate returns `.none` so it stays a true
arrow popover matching the mockup, rather than expanding to a full-screen sheet. The
hosting controller reports `preferredContentSize` (or uses
`.fittingSizeLevel`/`sizeThatFits`) so the popover hugs its content.

**Contents** (a `NavigationStack` so the Sort row can push inline):

1. **Density** — segmented Picker: Comfortable / Compact.
2. **Thumbnail** — segmented Picker: Left / Right / Hidden.
3. **Vote buttons** — Toggle.
4. **Sort** — a `NavigationLink` row showing the current sort's title + symbol; tapping
   pushes a sort picker (`QuickSwitchSortView`) listing the same groups as the toolbar
   menu (actives inline, a "Top" subgroup of time windows, comments inline), with a
   checkmark on the active sort. Selecting one pops back and applies immediately.

Every mutation calls `Haptics.tap()` (matching `PreferencesViewModel`). All controls
reflect external changes (e.g. someone changing density in Settings) because the view
model mirrors the preference streams.

**No auth gate.** Density, thumbnail, vote visibility, and sort all work signed-out;
no sign-in prompt is involved (unlike compose).

## Architecture

New files under `Scenes/PostList/QuickSwitch/`:

- `QuickSwitchView.swift` — SwiftUI popover root (the `NavigationStack` + Form).
- `QuickSwitchSortView.swift` — the pushed sort picker list.
- `QuickSwitchViewModel.swift` — `@MainActor @Observable`. Holds a
  `PreferencesServiceType` and mirrors `postDensity` / `thumbnailPosition` /
  `showVoteButtons` from their streams (same pattern as `PreferencesViewModel`);
  exposes `update…(_:)` setters that write the service and fire `Haptics.tap()`. Holds
  the current sort + the sort groups, and an `onSelectSort: (SortType) -> Void`
  callback supplied by the controller. Reads "active sort" via a closure so it always
  reflects the live feed.
- Presentation glue: a small helper on `PostListViewController` (e.g.
  `presentQuickSwitch(from:)`) that builds the hosting controller, wires the callbacks,
  configures the popover, and presents. Plus a `@objc quickSwitchTapped()` action and
  the `quickSwitchBarButtonItem` property.

Edits to existing files:

- `PostListViewController.swift` — add `quickSwitchBarButtonItem`, build it in
  `setup()` near `setupSortTypeMenu()`, include it in `updateTrailingBarButtonItems()`,
  add the tap handler + presentation. The Sort callback reuses the existing
  `sortTypeChanged(to:)` so the standalone sort button's menu stays in sync.

**Shared sort grouping (small refactor).** Extract the `actives` / `tops` / `comments`
sort groups (currently local to `setupSortTypeMenu`/`rebuildSortTypeMenu`) into one
shared definition (e.g. `PostSortMenu.groups` or static arrays on a small type),
consumed by both the existing `UIMenu` builder and the new `QuickSwitchSortView`. This
keeps a single source of truth for "which sorts, in what order, in what groups." If the
refactor proves risky, the fallback is for `QuickSwitchSortView` to define the same
groups locally — but the shared model is preferred.

**Live update.** No new observation: writing a pref through `PreferencesService` flows
to the already-running stream observers in `PostListViewController`, which reconfigure
visible cells. Sort flows through `sortTypeChanged(to:)` → `feedChanged()`.

## Data flow

```
tap sliders button
  -> presentQuickSwitch(from:)
       -> UIHostingController(QuickSwitchView(viewModel:))
       -> popover anchored to bar button (forced .popover on iPhone)

QuickSwitchView control change
  -> QuickSwitchViewModel.update…()  -> PreferencesService.<pref> = new + Haptics.tap()
       -> PreferencesService.<pref>Stream emits
            -> PostListViewController stream observer -> reconfigureVisibleCells()

QuickSwitchSortView selection
  -> viewModel.onSelectSort(sortType)
       -> PostListViewController.sortTypeChanged(to:)
            -> viewModel.didChangeSortType + feedChanged() + rebuildSortTypeMenu()
```

## Testing

- `QuickSwitchViewModelTests` (SpudTests):
  - Setting density/thumbnail/vote through the VM writes through to a fake/in-memory
    `PreferencesService`.
  - Changing the service externally updates the VM's mirrored values (stream mirror).
  - Selecting a sort invokes `onSelectSort` with the chosen `SortType`.
- Optional snapshot test of `QuickSwitchView` (light/dark). Snapshot tests are pinned
  to iPhone 14 Pro / portrait (or a config-pinned `.image(on:)`); only add if it earns
  its keep.
- Manual verification on a booted simulator: button appears on frontpage + community +
  saved feeds; popover stays a popover on iPhone; each control re-flows the visible
  cells live; sort change reflects in both the popover and the standalone sort button.

## Edge cases / notes

- **iPad vs iPhone:** popover anchors to the bar button on both; forced `.popover`
  keeps the arrow form on iPhone.
- **Feeds without compose:** Quick Switch still appears (left of sort).
- **Project generation:** new files require `make project` (XcodeGen) before building.
- **Concurrency:** `PreferencesService` is `@MainActor`; all popover code is main-actor.
- **`Spud.xcodeproj` is generated/gitignored**; LemmyKit is a pinned remote SPM package
  — no LemmyKit changes here.

## Follow-ups (not built here)

- Immersive feed layout + a real Compact↔Immersive toggle.
- Accent swatches and/or text-size in the popover, if wanted.
- "Set this sort as the feed's default."
