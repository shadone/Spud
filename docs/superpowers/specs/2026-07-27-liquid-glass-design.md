# iOS 26 Liquid Glass adoption

Date: 2026-07-27
Status: Approved, not yet implemented
Branch: `feat/liquid-glass`

## Problem

Spud is compiled against the iOS 26.2 SDK (Xcode 26.3) and its snapshot
references are recorded on iOS 26.3, so UIKit should hand the app Liquid Glass
chrome for free. It does not, because the app actively opts out.

`Spud/App/AppCoordinator.swift:46-70` installs global appearance proxies:

```swift
navigationBarAppearance.configureWithDefaultBackground()
navigationBarAppearance.backgroundColor = Theme.background
UINavigationBar.appearance().standardAppearance = navigationBarAppearance
// ... and the same for UITabBar, plus UITableView.appearance().backgroundColor
```

Setting an explicit `backgroundColor` on a bar appearance replaces the glass
material with a flat fill. The result is that on iOS 26 Spud renders as an
iOS 18-era app.

Beyond the opt-out, the app has adopted none of the iOS 26 design language:
zero uses of `UIGlassEffect` / `glassEffect` / `UIGlassContainerEffect`, 24
custom surfaces still on iOS 18-era `UIBlurEffect` materials, and a tab bar
still built with the legacy `setViewControllers` + `UITabBarItem` API (so no
`UISearchTab`, no tab minimization, no sidebar adaptivity).

## Goal

Make Spud look and feel like an app designed for iOS 26, and leave it ready for
iOS 27 without needing a toolchain we do not have yet.

## Decisions taken

These four were settled during design and are not open for re-litigation
without new information.

1. **Deployment target moves to iOS 26.0** (from 18.0). No `#available` forks,
   one visual language, one snapshot baseline. Cost: devices below iOS 26 are
   dropped.
2. **The True-Black (OLED) theme is retired.** It is the sole reason the opaque
   bar appearances exist. Liquid Glass bars are translucent by definition, and a
   theme whose entire purpose is forcing opaque chrome cannot coexist with them.
3. **Adoption depth is Tier 3**: chrome correctness, plus the new structural
   affordances, plus re-doing our own custom chrome on real glass. Not Tier 4
   (no Icon Composer / layered app icon work).
4. **iOS 27 is handled as forward-compatible hygiene only.** Only Xcode 26.3 /
   iOS 26.2 SDK is installed, so iOS 27-only APIs cannot compile. The
   adaptivity work from WWDC26 session 278 that *does* compile today is in
   scope; the iOS 27-only APIs are a documented follow-up.

## Principles

Drawn from Apple's *Adopting Liquid Glass* technology overview, which was
re-read during design rather than recalled:

1. **Deleting custom appearance code is the work.** The system provides glass
   when the app stops overriding it. Phase 0 is mostly deletion.
2. **Use bespoke glass sparingly.** It is for the topmost functional layer, not
   decoration. Overusing it distracts from content.
3. **Keep the content layer and the navigation layer distinct.** Glass belongs
   to navigation and controls, never to content.
4. **Do not pre-empt iOS 27.** Where iOS 27 changes a default (notably the
   scroll edge effect `.automatic` style), leave the default alone rather than
   pinning a value that becomes wrong.

## Non-goals

- Icon Composer / layered app icon (default plus the five `AppIconVariant`
  alternates). Self-contained project; deferred.
- iOS 27-only APIs: `prominentTabIdentifier`, iPhone `sidebar.preferredPlacement`,
  navigation `barMinimizationBehavior` / `barMinimizationSafeAreaAdjustment`,
  menu `preferredImageVisibility`, View Annotations for Ask Siri. Deferred until
  Xcode 27 is installed; recorded in the follow-ups section.
- Information-architecture redesign beyond the search-tab relocation that
  `UISearchTab` performs.
- `Spud/Scenes/ShareAsImage/` card rendering. Excluded by hard constraint (see
  Phase 3).
- SF Symbol motion effects and glass morph navigation transitions (Tier 4).

## Phase 0 - Foundation

The highest-value change and almost entirely deletion. After this phase the app
already reads as an iOS 26 citizen; everything after is refinement.

### 0.1 Deployment target

`Spud/project.yml`: `deploymentTarget.iOS` from `"18.0"` to `"26.0"`, then
`make project`. Verify every target inherits it (app, extensions, frameworks,
test targets).

### 0.2 Remove the appearance opt-out

Delete the whole body of `AppCoordinator.configureAppeareance()`:
- the `UINavigationBarAppearance` block and its three `UINavigationBar.appearance()`
  assignments,
- the `UITabBarAppearance` block and its two `UITabBar.appearance()` assignments,
- `UITableView.appearance().backgroundColor = Theme.background`.

The method then has no body and is removed along with its call site in `init`.

### 0.3 Retire True-Black

Remove:
- `AppTheme.trueBlack` case and `AppTheme.usesTrueBlackBackgrounds`,
- `ThemeManager.trueBlackFlag`, `ThemeManager.usesTrueBlackBackgrounds`, and the
  private `TrueBlackFlag` class,
- the entire `Theme` enum in `SpudUIKit/Theme/Theme.swift` - it exists only as
  the True-Black shim - sweeping its 71 call sites to the system colors each
  token wraps (`Theme.background` to `.systemBackground`, `Theme.groupedBackground`
  to `.systemGroupedBackground`, and so on).

`ThemeManager` itself stays: it still owns `AccentColor` and the
`accentColorBox` non-isolated accent accessor. `AppTheme` stays with three
cases (`system`, `light`, `dark`).

`Theme.secondaryGroupedBackground` is the one token that is not a pure
pass-through (under True-Black it lifted cells to `white: 0.07`). Its
non-True-Black branch is `.secondarySystemGroupedBackground`, so the sweep is
still a straight substitution.

### 0.4 Preference migration

`appTheme` persists through `@UserDefaultsBacked` as its `String` raw value. A
device that stored `"trueBlack"` would fail to decode against the narrowed
enum. Add an explicit remap at the decode boundary in
`Spud/Services/Preferences/PreferencesService.swift`: a stored `"trueBlack"`
resolves to `.dark` and is rewritten on next persist.

This must be a real migration, not reliance on a default-value fallback, so
that the user's *choice* degrades to the nearest equivalent rather than
silently resetting to `.system`.

### 0.5 Tests touched

`SpudUIKitTests/ThemeResolutionTests.swift` loses its `trueBlack` assertions.
Add a test for the `"trueBlack"` to `.dark` migration.

### Acceptance

- App builds and launches with an iOS 26.0 floor.
- Navigation bars, tab bar, sheets, popovers, menus and alerts render the stock
  Liquid Glass material; content scrolls visibly beneath the bars.
- A device with `"trueBlack"` persisted launches into `.dark` with no reset to
  `.system`.
- `SpudUIKit/Theme/Theme.swift` is deleted, and
  `grep -rn '\bTheme\.' --include='*.swift'` returns no hits (matches of
  `ThemeManager.` do not count - the pattern is the bare `Theme` enum).

## Phase 1 - Chrome correctness

Audit what the system now provides and stop interfering with it.

### 1.1 Sheets and popovers

Audit the 47 `sheetPresentationController` / `popoverPresentationController` /
`modalPresentationStyle = .popover` sites for custom background views and
visual-effect backdrops; remove them. Apple's guidance is explicit that custom
popover/sheet backgrounds should be removed for a consistent system experience.

Also check content clearance against the increased sheet corner radius, and that
content peeking between an inset half-sheet and the display edge looks right.

### 1.2 Scroll edge effects

For every custom bar that overlays a scroll view, ensure the owning view
controller calls `setContentScrollView(_:for:)`, and that container views of
overlaying controls carry `UIScrollEdgeElementContainerInteraction` so the edge
effect shapes itself around them.

**Leave the style at `.automatic`.** In iOS 27 `.automatic` stops switching
between `soft` and `hard` and grows its own visuals; any `.soft` override
introduced now becomes wrong on iOS 27. If an override already exists, remove it
rather than re-pinning it.

### 1.3 Concentric corners

135 hardcoded `cornerRadius` sites exist across `Spud/` and `SpudUIKit/`. Do not
convert them wholesale. Triage rule:

- Nested inside a rounded or glass container (so the curvature should be
  concentric with its parent): convert to `UIView.cornerConfiguration` /
  `UICornerConfiguration`.
- A free-standing content shape whose radius is part of the content's identity
  (avatars, thumbnails, media tiles, share-card artwork): leave alone.

Expect a minority to change. Record the triage outcome per site in the
implementation plan so the reviewer can check the judgement rather than the
mechanics.

### 1.4 Buttons

Audit the 59 `UIButton.Configuration` sites:
- A button that floats **over** content (overlay controls, media chrome,
  floating actions) becomes `.glass()` or `.prominentGlass()`.
- A button that sits **in** content (inline row actions, form buttons) keeps
  `.filled()` / `.tinted()` / `.plain()`.

### 1.5 Section header capitalization

iOS 26 lists use title-style capitalization for section headers. Fix the
manually uppercased headers: `InstanceDetailViewController.swift:495`
(`captionLabel.text = label.uppercased()`) and `InstanceAdminsView.swift:197`
(`titleLabel.text = title.uppercased()`).

The other `.uppercased()` hits are single-letter avatar/icon monograms and
language codes; leave them.

### 1.6 Toolbars and bar items

- Group toolbar items that perform related actions; use
  `UIBarButtonItem.fixedSpace(_:)` to separate groups that share a background.
- Hide the whole item via `UIBarButtonItem.isHidden`, never by hiding the view
  inside it.
- Do not mix text and icon items within a group that shares a background.
- Every icon-only bar item keeps an accessibility label.
- Where a bar button carries a hand-drawn count decoration, replace it with
  `UIBarButtonItem.badge`. (The Inbox *tab* badge is not this - it is set via
  `applyUnreadBadge` on the tab bar item and moves to `UITab` in Phase 2.2.)

### 1.7 Accessibility and display settings

Verify the app under Reduce Transparency, Increase Contrast, and Reduce Motion.
Stock components adapt automatically; our custom surfaces are where this fails.
This check is repeated after Phase 3.

### Acceptance

- No custom backgrounds remain on sheets or popovers.
- No `scrollEdgeEffectStyle` overrides remain.
- Buttons floating over content use a glass configuration; in-content buttons do
  not.
- Section headers are title case.
- App is legible and correct under all three accessibility settings.

## Phase 2 - Structure

### 2.1 Migrate to `UITab`

`Spud/Scenes/MainWindow/MainWindow.swift:390-400` builds the tab bar with
`tabBarController.setViewControllers([...])` and per-controller `tabBarItem`
assignments. Current order: Posts (split) | Communities | Search | Inbox |
Account.

Migrate to `setTabs(_:animated:)` with `UITab` objects, and make the Search tab
a **`UISearchTab`**. The system separates a search tab from the others and places
it at the trailing end automatically. This is a deliberate, user-visible IA
change: Search moves from position 3 to last.

### 2.2 Tab identity, not tab index

`MainWindow` addresses the Inbox tab by index (`Self.inboxTabIndex`, with a
comment pinning Inbox to index 3) for badge updates, and three sites index into
`tabBarController.viewControllers`. Replace all of it with `UITab` identifiers.

This is the change most likely to break UI tests. `SpudUITests` and
`IPadSplitUITests` must be audited for tab-index and tab-order assumptions -
both because indices become identifiers and because Search physically moves.

### 2.3 Tab bar minimization

Set `tabBarMinimizeBehavior = .onScrollDown` so the tab bar recedes and the feed
gets the full screen.

### 2.4 Background extension

Adopt `UIBackgroundExtensionView` behind hero imagery in the iPad split's detail
column - post images and community / person banner headers - so content reads as
extending under the sidebar.

### 2.5 `tabSidebar` spike (evaluate, do not assume)

`UITabBarController.Mode.tabSidebar` lets a tab bar adapt into a sidebar on iPad.
Spud already ships a bespoke `MainWindowSplitViewController` (sidebar + detail),
so adopting `tabSidebar` on top of it risks two competing sidebars.

Phase 2 spikes this on a throwaway commit and then either adopts it or records
in the ADR why it was rejected. A rejection is an acceptable outcome; an
unexamined omission is not.

### Acceptance

- Tabs are `UITab` objects; Search is a `UISearchTab` and renders at the
  trailing end.
- No code addresses a tab by index.
- Tab bar minimizes on scroll down.
- UI tests pass against the new tab order.
- The `tabSidebar` decision is recorded either way.

## Phase 3 - Bespoke glass

Convert our own chrome from iOS 18-era `UIBlurEffect` materials to
`UIGlassEffect`, grouping co-located elements in a `UIGlassContainerEffect` so
they merge and morph correctly and render efficiently.

### 3.1 Convert

- `Spud/Scenes/MediaViewer/MediaViewerViewController.swift:86` and `:143` - the
  top and bottom control chrome. The clearest win: floating controls over
  photos is exactly what glass is for. These two belong in one container effect.
- `Spud/Utils/Views/LowResPreviewPillView.swift:33`
- `Spud/Scenes/Common/Toast/ToastPresenter.swift` - floats over content.
- `Spud/Scenes/Community/Content/CommunityHeaderView.swift:205`
- `Spud/Scenes/Account/InstanceDetail/InstanceDetailViewController.swift:636`

### 3.2 Deliberately not converted

- **`Spud/Scenes/Shared/NsfwBlurOverlayView.swift:24`** - this is a *content
  obscurer*, not chrome. Glass is translucent by design; an NSFW cover that lets
  content through is a defect. Stays a `UIBlurEffect`.
- **All of `Spud/Scenes/ShareAsImage/`** - hard constraint from
  `Spud/CLAUDE.md`: share cards are fixed designed artifacts that must render
  identically off-screen, and must never use `UIVisualEffectView` (the NSFW
  spoiler there is `CIGaussianBlur` precisely for this reason). Untouched by
  this project.

### 3.3 Shared tokens

Add a small tokens file under `SpudUIKit/Design/` holding the glass style and
pill-corner constants the converted sites share, so five call sites do not each
invent their own radius and material.

**Tokens only - not a wrapper framework.** Apple's guidance is that the win
comes from using stock components and applying glass sparingly; a `GlassKit`
abstraction layer would re-introduce exactly the indirection Phase 0 deletes.

### Acceptance

- The listed surfaces use `UIGlassEffect`; co-located ones share a
  `UIGlassContainerEffect`.
- `NsfwBlurOverlayView` and `ShareAsImage/` are untouched.
- Re-run the Reduce Transparency / Increase Contrast / Reduce Motion pass; the
  converted surfaces stay legible.
- No new abstraction layer over UIKit's glass API.

## Phase 4 - Adaptivity hygiene (iOS 27 readiness)

WWDC26 session 278 requires apps to be fully resizable: iPhone apps become
resizable under iPhone Mirroring on macOS 27 and when running on iPad. All of
the below compiles on the current toolchain.

Already clean, verified during design:
- Scene lifecycle adopted (`SceneDelegate: UIWindowSceneDelegate`). Required in
  iOS 27 - apps built with the latest SDK that lack it fail to launch.
- Zero `userInterfaceIdiom` layout checks.
- Zero interface-orientation layout checks.

Remaining work - the seven `UIScreen.main` uses:

Hairline widths, to `traitCollection.displayScale`:
- `Spud/Scenes/Activity/ActivityFootprintRailView.swift:38`
- `Spud/Scenes/Person/Content/PersonHeaderView.swift:285`
- `Spud/Scenes/Common/Toast/ToastPresenter.swift:162`
- `Spud/Scenes/Community/Content/CommunityHeaderView.swift:318`
- `Spud/Scenes/PostDetail/Content/PostDetailCrossPostsCell.swift:97` (already
  carries a comment acknowledging `UIScreen.main` is soft-deprecated)

Sizing content off the screen - genuine adaptivity bugs that will visibly break
under a resized scene, to view / superview bounds:
- `Spud/Scenes/Account/EditProfile/ProfileBannerHeaderView.swift:314`
- `Spud/Scenes/Account/InstanceDetail/Components/InstanceWrapView.swift:36`

### Acceptance

- No `UIScreen.main` references remain in shipped targets.
- Layout is correct at arbitrary scene sizes, not just device-sized ones.

## Testing strategy

**Snapshots are the dominant cost.** 517 git-annex-tracked PNG references across
63 test classes, recorded on iPhone 17 Pro / iOS 26.3.x. Phase 0 changes chrome
on essentially every screen, so nearly all of them churn.

Two re-record waves, not four:
1. After Phase 0, once foundation is stable.
2. After Phase 3, covering the bespoke-glass surfaces.

Phases 1, 2 and 4 re-record only the classes they actually touch. Follow
`SpudSnapshotTests/CLAUDE.md`: `make snapshot` on the reference device, re-record
**one class at a time**, `git add` only the explicit refs changed, and run
`git annex restage` when cosmetic modified markers appear on committed refs.

Other layers:
- **Unit**: the `"trueBlack"` to `.dark` preference migration;
  `ThemeResolutionTests` narrowed to three cases.
- **UI tests**: audited for tab-index and tab-order assumptions broken by 2.1
  and 2.2.
- **Accessibility**: Reduce Transparency, Increase Contrast, Reduce Motion -
  after Phase 1 and again after Phase 3.
- **Manual**: iPhone 17 Pro and iPad Pro 11-inch (M5), both orientations, plus a
  resized-scene check for Phase 4. Respect the single-booted-simulator rule.

## Documentation

- `docs/features/`: the appearance / theming capability doc (True-Black removal
  is user-visible behavior), plus **both** README index sections - the
  capability table and the coverage-by-area map.
- **ADR**: retiring True-Black reverses a shipped product decision and the
  `tabSidebar` spike needs its outcome recorded. One ADR under `docs/adr/`
  covering the Liquid Glass adoption, the True-Black retirement, and the
  `tabSidebar` decision.
- `Spud/CLAUDE.md`: new iOS 26.0 floor, the removed `Theme` token layer, and the
  `UITab`-identity convention replacing tab indices.

## Risks

| Risk | Mitigation |
|---|---|
| True-Black removal is a user-visible regression | Decode-time migration to `.dark`, plus a release note. Accepted as a deliberate decision. |
| iOS 26.0 floor drops older devices | Accepted; decision taken during design. |
| 517-ref snapshot churn on git-annex | Two batched re-record waves; one class at a time; explicit `git add` paths. |
| Glass over dark content may fail contrast on Phase 3 surfaces | Accessibility pass after Phase 1 and Phase 3. |
| `UITab` migration breaks UI tests silently | UI-test audit is explicit acceptance criteria for Phase 2, not an afterthought. |
| `tabSidebar` collides with the bespoke split view | Scoped as a spike with an explicit record-either-way outcome. |
| Shared checkout: local `main` advances mid-task | Work in the `feat/liquid-glass` worktree; re-check `main..feat/liquid-glass` and file overlap immediately before merging. |

## Follow-ups (blocked on Xcode 27)

Recorded here so they are not rediscovered later:

- `UITabBarController.prominentTabIdentifier`
- iPhone sidebar opt-in: `tabBarController.sidebar.preferredPlacement = .sidebar`,
  gated on `sidebar.isAvailable`
- `UINavigationItem.barMinimizationBehavior` and
  `barMinimizationSafeAreaAdjustment`
- Re-evaluate scroll edge effect styles once iOS 27's revised `.automatic`
  visuals ship
- `UIMenuElement.preferredImageVisibility`
- View Annotations (annotating views with `AppEntity`) for the Ask Siri menu
  entry point. Spud already ships App Intents and entities
  (`CommunityEntityQuery`, `AccountEntityQuery`), so this is a natural fit.
- Icon Composer layered app icon for the default icon and the five
  `AppIconVariant` alternates
