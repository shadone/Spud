# iPad / split-view polish

- **Date:** 2026-06-30
- **Status:** design — pending implementation
- **Surfaces:** `ipad` (regular size class). iPhone / compact is explicitly unchanged.
- **Targets touched:** `Spud` (app target only — scenes, MainWindow routing)
- **Replaces/updates docs:** new `docs/features/ipad-layout.md` capability doc + README capability table and "Feature coverage by area" map

## Summary

Spud is a universal app, but only the **Posts** tab uses the iPad two-column
(master–detail) split layout. The other four tabs are single-column, several
SwiftUI surfaces strand whitespace or stretch full-bleed on a wide canvas, and a
few iPad presentation idioms (popover anchoring, sheet detents) are silently
wrong. This iteration closes an 8-item gap list across three tiers:

- **Tier A — adaptive layout polish (#3–#8):** width caps + adaptive grids +
  correct iPad presentation idioms. No navigation change; regular-size-class only.
- **Tier B — feed switcher popover (#1):** on iPad, picking a feed becomes a
  navbar popover instead of popping away the always-visible primary column.
- **Tier C — Communities reading split (#2):** entering a community on iPad opens
  a 2-column `[community feed | post detail]` reading context; browse
  (subscribed list + Discover) stays full-width.

## Background — verified current state

Verified against `main` @ `d8b44093` this session:

- **Only the Posts tab is a `UISplitViewController`** (`MainWindowSplitViewController`).
  Communities / Search / Inbox / Account are plain `UINavigationController` stacks
  (`MainWindow.swift:256-306`). Collapse/expand on rotation is handled for Posts.
- **`pushIntoCurrentContext`** (`MainWindow.swift:618-628`) hard-codes
  "only the Posts tab is split": `selected === splitViewController` → `pushDetail`;
  any other tab → plain push. A second split tab would fall through to the
  Posts-tab fallback (hijack).
- **Feed switcher (#1):** `MainWindowSplitViewController.swift:60-83` puts
  `FeedSwitcherViewController` at index 0 in the primary nav stack, with the post
  list pushed on top. The system left-edge back gesture pops to it — which on iPad
  replaces the persistently-visible primary column with the picker. Distinct from
  the QuickSwitch popover (sort + offline download, `slider.horizontal.3`,
  `PostListViewController.swift:830-855`), which is already iPad-correct via
  `ForcePopoverDelegate`.
- **Community screen (#2):** `CommunityViewController` already composes the
  community info (`CommunityHeaderView` — banner, icon, title, subscribers/posts
  counts, vitality, description/rules markdown, Subscribe) as the **scrolling
  header atop the community's post feed** (`CommunityViewController.swift:18-21`,
  `219-223`). The feed is a `PostListViewController` driven by `FeedType.community`,
  embedded as a child. So community info needs no new screen or extra column — it
  lives in the feed (list) column's header.
- **#3 Discover rails:** `DiscoverView.swift` uses `ScrollView(.horizontal)`
  (lines 261, 285, 317) of fixed `.frame(width: 178, ...)` cards (530, 590).
- **#4/#7 banner:** `AccountView.swift:34` renders the banner full-bleed via
  `.listRowInsets(EdgeInsets())`; `ProfileBannerHeaderView.swift:292` downsamples
  against `UIScreen.main.bounds.width` (the full iPad width).
- **#5 Account list:** `AccountList/AccountListViewController.swift` forces a
  bottom sheet (phone idiom) rather than an iPad popover.
- **#6 Composer/NewPost detents:** `ComposerViewController.swift:252` and
  `NewPostViewController.swift:583,621` read `navigationController.sheetPresentationController`
  **without first setting `modalPresentationStyle`**. On iPad the default is
  `.formSheet`, for which that property is `nil`, so the detents are silently
  dropped.

## Goals

- iPad regular size class makes good use of the canvas: no stranded whitespace,
  no full-bleed filmstrips, correct popover/sheet idioms.
- Picking a feed on iPad never replaces the always-visible primary column.
- Reading a community on iPad is 2-column `[community feed (+info header) | post
  detail]`; browsing communities (subscribed list + Discover) is full-width.
- iPhone / compact behavior is byte-for-byte unchanged (every change is gated on
  the regular size class or auto-collapses).
- Accessibility (VoiceOver focus order across columns, popover label/trait) and
  the three doc tiers are part of "done".

## Non-goals (this iteration)

- **No multi-split for Search / Inbox / Account.** Scoped out; Communities only.
- **No three-column (Mail-style) Communities layout** and **no persistent
  communities sidebar.** Community switching is "back out to browse" (Option 1).
- **No change to where community info renders.** It stays the feed header; we do
  not build a separate community "About" screen or detail-column info pane.
- **No Cards/Immersive feed presets or other Scout-redesign work.**
- **No iPad-specific keyboard shortcuts / pointer interactions** beyond what the
  changed controls inherit for free.

## Design

### Tier A — Adaptive layout polish (#3–#8)

All gated to the regular size class (or naturally adaptive), so compact is
untouched. Each is independent and independently shippable.

- **#3 Discover rails → adaptive grid.** Replace each fixed-width
  `ScrollView(.horizontal)` rail with `LazyVGrid(.adaptive(minimum: 160))` (or a
  size-class-conditional layout: keep the horizontal rail in compact, adaptive
  grid in regular). Cards fill the wide canvas instead of stranding space.
- **#4 Profile banner width cap.** Cap the banner's rendered content width
  (`frame(maxWidth: 600)`, centered) so it is not a 1024pt filmstrip on iPad.
  Same treatment for `PersonHeaderView`'s banner.
- **#7 Banner downsample cap.** In `ProfileBannerHeaderView` (and `PersonHeaderView`
  if it shares the path), cap the downsample fetch width to `min(width, 600)`
  rather than full `UIScreen.main.bounds.width`.
- **#5 Account list popover.** On iPad, present the account switcher as a popover
  anchored to the "Switch account" row instead of forcing `.pageSheet`; keep the
  bottom sheet in compact. Anchor via the row's source view/rect.
- **#6 Composer / NewPost detents.** Set `modalPresentationStyle = .pageSheet` on
  the wrapping navigation controller **before** the `sheetPresentationController`
  detent block, so detents apply on iPad. (`.pageSheet` keeps the detent behavior;
  the default `.formSheet` is what nils the controller.) Applies to both
  `ComposerViewController` and the three `NewPostViewController` factory paths.
- **#8 Discover directory rows width cap.** Cap the community-directory
  `LazyVStack` to `maxWidth: 700`, centered, so rows don't stretch full-bleed.

### Tier B — Feed switcher as a popover on iPad (#1)

- **Regular size class:** add a tappable navbar **title control** to
  `PostListViewController` — the current feed name + `chevron.down` — that presents
  `FeedSwitcherViewController` as a **popover** anchored to the title. The primary
  column is never popped away.
- **Compact:** unchanged — keep the existing beneath-the-list backstack reached by
  the system left-edge swipe.
- **Single source of truth:** both paths drive the same `FeedSwitcherViewController`
  and its existing `onSelectFeedType` / `onBrowseAllCommunities` callbacks. The only
  fork is the presentation path, keyed on `traitCollection.horizontalSizeClass`,
  re-evaluated on `traitCollectionDidChange` (e.g. iPad multitasking resize).
- The QuickSwitch (sort/offline) button is untouched.

### Tier C — Communities 2-column reading split (#2)

- **Communities tab stays a full-width browse nav stack:** `SubscriptionsViewController`
  → `[Explore]` → `DiscoverView`. Both render full-width on iPad (Discover gains
  only Tier A's adaptive grid).
- **Entering a community opens a 2-column reading context:** `CommunityViewController`
  (existing header + feed) on the **primary (list)** side; **post detail** on the
  **secondary (wide)** side. Community info is the header atop the primary column —
  reused as-is.
- **Empty detail state:** the secondary column shows a "Select a post" placeholder,
  reusing the Posts tab's `PostDetailOrEmptyViewController` empty state.
- **Tapping a post** in the community feed fills the secondary column instead of
  pushing full-screen.
- **Compact (iPhone):** the reading context auto-collapses to single-column
  (community feed → push post detail) — identical to today.
- **Router generalization:** generalize `pushIntoCurrentContext` so it detects
  *any* active split tab (not just the Posts split by identity) and routes detail
  pushes into that tab's secondary column. Deep links / Spotlight / Handoff that
  resolve to a post while the Communities reading context is active must land in
  its secondary column, not hijack the Posts tab.

**Containment mechanic — derisk as implementation task 1 (a 30-min iPad-sim
spike), NOT a design unknown.** Two candidates both deliver this exact UX:

1. A nested `UISplitViewController` pushed onto the browse nav stack when a
   community is opened (collapses on compact).
2. The Communities tab is itself a `UISplitViewController`, with the browse
   levels full-width and display modes / `show(_:)` driving the reveal of the
   secondary column on community entry.

The spike picks whichever collapses cleanly on compact and keeps a single navbar
(no double nav bars) before the rest of Tier C builds on it. If neither is clean,
fall back to routing community reading through the existing Posts split (the
Option 3 escape hatch) and flag it for re-decision.

## Testing

- **Snapshots:** the app-level suite pins iPhone 17 Pro and does not exercise iPad
  regular width. Add **iPad-targeted snapshot configs** (`.image(on:)` with an iPad
  trait/size) for: Discover (adaptive grid, populated), profile + community
  banners (width-capped), and the Communities reading split (empty detail + loaded
  detail). Record on the reference device/runtime per CLAUDE.md.
- **UITest (required):** snapshots render VCs in isolation and will NOT catch the
  routing/column wiring (same lesson as the navbar child-VC bug). Add a UITest that
  walks the real iPad path: Communities → tap community → assert 2-column → tap post
  → assert detail in the secondary column → verify the feed-switcher title popover
  on the Posts tab.
- **Accessibility:** VoiceOver focus order across the two columns; the feed-switcher
  title control and the account-list popover carry correct label + trait; Dynamic
  Type on the adaptive Discover grid.
- **Regression guard:** a compact-width pass (iPhone) confirming Tier B/C behavior
  is unchanged.

## Docs to update

- New `docs/features/ipad-layout.md` (capability doc): behavior/rules + Given/When/Then
  scenarios for the adaptive layouts, the feed-switcher popover, and the Communities
  reading split. `Surfaces: ipad`.
- README capability table **and** "Feature coverage by area" map (both sections).
- Reconcile adjacent docs that describe the Communities tab / feed switcher /
  Discover so they note the iPad behavior.

## Phasing (for the implementation plan)

1. **Tier A (#3–#8)** — low-risk, independent, independently shippable. Lands first.
2. **Tier B (#1)** — feed-switcher popover.
3. **Tier C (#2)** — containment spike (task 1) gates the rest: reading split,
   empty state, router generalization, then tests + docs.

## Open questions / tunable defaults

- **#1 affordance:** tappable feed-name title + `chevron.down` → popover (chosen).
  Alternative: a dedicated leading navbar button. Title-as-control is the closer
  iOS idiom.
- **Tier A width caps:** banners ~600pt, directory rows ~700pt, Discover grid
  `minimum: 160`. Tunable on the iPad sim during implementation.
