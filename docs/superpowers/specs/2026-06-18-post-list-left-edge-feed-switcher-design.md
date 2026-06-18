# Post list — left-edge feed switcher

Date: 2026-06-18
Surface: Posts tab (`MainWindowSplitViewController`)

## Problem

Tapping the post-list navbar title presents the feed switcher (All / Local /
Subscribed / Saved / Browse all communities) as a modal "leading drawer". That
title-tap trigger was a misunderstanding. The switcher should instead be reached
by **swiping in from the left edge** while on the post list — the muscle memory
the old "swipe the list in from the left" gesture had.

## Decision

Make the feed switcher the **view controller beneath the post list** in the Posts
tab's primary/compact navigation stack: `[feedSwitcher, postList]`. The left-edge
swipe is then just the **system interactive back gesture** (pop) — it reveals the
switcher with no custom gesture and no custom interactive transition. Once a post
detail is pushed (`[feedSwitcher, postList, postDetail]`), the left edge means the
normal "back to the list", so scoping falls out automatically.

This replaces the modal drawer entirely. The drawer becomes a full-screen pushed
screen on iPhone and a primary-column (sidebar) list on iPad. The dimmed-overlay
look is intentionally dropped.

### Why this works with the existing navigation machinery

The Posts tab is a `UISplitViewController`; `postListNavigationController` is its
`.primary` **and** `.compact` column. Both already have
`enableForwardNavigationGesture()`, which installs `ForwardNavigationGestureDriver`.
That driver re-vends the system left-edge back gesture with
`gestureRecognizerShouldBegin → viewControllers.count > 1`. With the stack
`[feedSwitcher, postList]` (`count == 2`) the back-swipe is live and pops to the
switcher — for free.

The driver's `ForwardStackReducer` also makes the pop/re-push coherent:

- **Swipe back to switcher** pops `postList`; the reducer prepends it to the forward
  stack, so a *right*-edge forward swipe re-pushes the same instance — a free "undo,
  back into my current feed".
- **Tap a feed** re-pushes the *same* `postList` instance. The reducer's "append-push
  of exactly `forwardStack.first` → consumed" branch absorbs it, leaving a clean
  forward stack. (Reusing the same instance also preserves the feed observation.)
- The initial `setViewControllers([...], animated: false)` is a structural change the
  reducer explicitly ignores, so it never pollutes the forward stack.

## Out of scope

- **Navbar title behaviour.** It has a separate design landing later. Here the title
  is reduced to a plain feed-name label; the chevron/tap that opened the modal is
  removed. The separate design supersedes this.
- **Interactive *dismiss* of the switcher.** The system pop animation is the only
  transition; there is no overlay/drawer animator to tune.
- **Re-selecting the Posts tab to return to the feed** when the switcher is showing.
  Possible future polish; not handled now.

## Changes

### A. `MainWindowSplitViewController`

- Build the feed switcher and set the primary/compact stack to
  `[feedSwitcher, postListVC]` (currently just `[postListVC]`, line ~55).
- Wire the switcher callbacks here (the post list and nav controller are in scope):
  - **Select feed:** `postListVC.showFeed(feedType)` then
    `postListNavigationController.pushViewController(postListVC, animated: true)`.
    Switch the feed first so the list animates in already showing the new feed.
  - **Browse all communities:** re-push `postListVC` with `animated: false` (so the
    Posts tab is restored to its normal `[feedSwitcher, postList]` state rather than
    left stranded on the switcher), then `tabBarController?.selectedIndex = 1`.
- Give the switcher a short title ("Feeds") so the post list's back button reads
  "‹ Feeds".

### B. `PostListViewController`

- Delete the modal-drawer machinery: `quickSwitchTapped`, the
  `drawerTransitioningDelegate` property, and the custom title button
  (`quickSwitchTitleButton`, `makeQuickSwitchTitleButton`, `updateQuickSwitchTitle`).
- `applyNavigationTitle` / `configureTitle` collapse to setting
  `navigationItem.title = viewModel.navigationTitle` (plain label, both branches).
- When `showsQuickSwitch` (the main feed sits atop the switcher), set
  `navigationItem.leftItemsSupplementBackButton = true` so the leading compose button
  (`setupComposeButton` sets `leftBarButtonItem` on frontpage feeds) and the
  "‹ Feeds" back button coexist instead of the compose item hiding the back button.
  On the Saved feed (no compose) the back button shows normally.
- Expose `currentFeedType` (forwarding `viewModel.feed.feedType`) for the switcher's
  checkmark provider.
- `showFeed(_:)` / `switchFeed(to:)` are unchanged and continue to drive in-place
  feed switches (deep links, App Intents, and now the switcher selection).

`showsQuickSwitch` keeps its meaning ("this is the primary feed atop the switcher")
and now gates the back-button supplement. Optional: rename to a clearer
`sitsAtopFeedSwitcher` / `isPrimaryFeed`. Other call sites pass `false`
(community/account/subscriptions feeds) and are unaffected.

### C. Feed switcher view controller

- Rename `QuickSwitchDrawerViewController` → `FeedSwitcherViewController` (the
  "drawer" name and the doc comment about "sliding in from the leading edge when the
  user taps the feed title" are now inaccurate). Folder may follow:
  `QuickSwitch/` → `FeedSwitcher/`.
- It is a full-screen pushed list now (the static rows are unchanged: All / Local /
  Subscribed / Saved, then Browse all communities). Title "Feeds".
- It is long-lived (created once, lives at the bottom of the stack), so the init-time
  `activeFeedType` would go stale. Replace it with an injected
  `currentFeedType: () -> FeedType?` provider; recompute the active row and
  `tableView.reloadData()` in `viewWillAppear` so the checkmark is correct every time
  the switcher is revealed. (`isActive` comparison logic is unchanged — by kind,
  ignoring sort.)
- The per-row frontpage sort can resolve from the current default sort at build/
  selection time rather than a baked init value; low importance, keep simple.

### D. Delete `LeadingDrawerPresentation.swift`

`LeadingDrawerPresentationController`, `LeadingDrawerAnimator`, and
`LeadingDrawerTransitioningDelegate` are only used by the removed modal present.
Delete the whole file. Run `make project` (XcodeGen) after removing the source.

## Testing

- **`ForwardStackReducer` unit tests** — add explicit cases for the new flow even
  though the generic branches already cover them: (1) `[switcher, postList]` pop →
  forward stack `[postList]`; (2) re-push the same `postList` instance → forward stack
  consumed to empty; (3) `setViewControllers(animated: false)` → forward stack
  unchanged.
- **Manual simulator verification** (the primary gate — UIKit navigation glue):
  - iPhone: launch shows the post list; left-edge swipe reveals the switcher with the
    current feed checked; tapping a feed returns to the post list showing that feed
    with the checkmark moved; right-edge forward swipe from the switcher restores the
    current feed; the compose pencil and "‹ Feeds" back button both show on frontpage
    feeds; the Saved feed shows the back button; "Browse all communities" opens the
    Communities tab and leaves the Posts tab on its feed (not the switcher).
  - iPad: the same, with the switcher appearing in the primary (sidebar) column; the
    secondary/detail column is unaffected by feed switches.
- **Optional** snapshot of `FeedSwitcherViewController` as a pushed screen
  (iPhone 14 Pro / portrait, per the snapshot harness).
- Sanity-check `MainWindow.display(...)` (the post-detail push path) makes no
  assumption that the post list is at index 0 of `postListNavigationController`; the
  pre-pushed switcher must not change how the detail is shown on iPhone or iPad.

## Risks

- **iPad sidebar feel.** The switcher renders in the narrow primary column on iPad
  rather than as an overlay. Accepted as the chosen trade-off.
- **Leading bar crowding.** "‹ Feeds" + compose on the leading side is busier than a
  bare title; acceptable and standard. If it reads poorly, the fallback is moving
  compose to the trailing slot beside the sort menu.
- **Interim accessibility/title.** Until the separate title design lands, the only
  labeled entry to the switcher is the "‹ Feeds" back button (plus the edge swipe).
  This is why the back button is kept visible rather than hidden.
