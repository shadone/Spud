# ADR-0002: Adopt iOS 26 Liquid Glass by deletion, retire True Black, reject the tab sidebar

**Date**: 2026-07-27
**Status**: accepted
**Deciders**: Denis

Three decisions taken together during the Liquid Glass adoption, recorded in one
document because they are entangled: the theme retirement is a *consequence* of
adopting glass, and the tab-sidebar rejection is the same structural argument as
an iPad split-view decision made one container level down.

## Context

iOS 26 replaces UIKit's bar chrome with the Liquid Glass material. The system
supplies it for free — but only to apps that stop supplying their own. Spud did
not: `AppCoordinator` installed explicit `UINavigationBarAppearance` /
`UITabBarAppearance` background colours, and several sheets and popovers painted
their own flat fills. An explicit `backgroundColor` on a bar appearance replaces
the glass material outright, so on iOS 26 the app rendered as a pre-26 app.

Those overrides were not arbitrary. They existed to serve the **True Black**
theme, a Dark variant whose whole purpose was forcing opaque black bars on OLED
displays. So "let the system draw the bars" and "keep True Black" were directly
in conflict.

At the same time, iPadOS offers `UITabBarController.Mode.tabSidebar` — the
system tab bar that can present itself as a sidebar. Spud's iPad layout is
already a two-column `MainWindowSplitViewController`, so adopting it would put a
system sidebar in front of an app sidebar.

## Decision

1. **Adopt Liquid Glass by deleting Spud's own appearance code**, and raise the
   deployment floor to **iOS 26.0** so the material is unconditionally available.
2. **Retire the True Black theme.** The picker is System / Light / Dark; a
   persisted True Black selection degrades to Dark at decode time. The `Theme`
   token layer is deleted; call sites use system semantic colours directly.
3. **Reject `UITabBarController.Mode.tabSidebar`.** Spud keeps its plain tab bar
   plus its own split view on iPad.

## Alternatives Considered

### Alternative 1: Keep the iOS 18 floor and gate glass behind `#available(iOS 26, *)`

- **Pros**: no user left behind on iOS 18-25; the change could ship earlier.
- **Cons**: every glass surface needs a non-glass twin, so the appearance code
  being deleted would have had to be *kept and maintained* alongside the new
  path — the opposite of the payoff. True Black could not be retired either,
  because the pre-26 branch still needs it. Snapshot references would need two
  sets.
- **Why not**: the value of this change is almost entirely subtractive. A
  compatibility branch preserves exactly the code the change exists to remove,
  and doubles the surface every future UI change has to satisfy.

### Alternative 2: Adopt glass but keep True Black as an opaque-bar override

- **Pros**: no user-visible feature removal; OLED users keep pure-black
  backgrounds.
- **Cons**: True Black's mechanism *is* forcing an opaque bar background, which
  is precisely the override that suppresses the glass material. Keeping it means
  keeping a theme whose selection silently opts the user out of the new design,
  and keeping the whole theme-aware colour-token indirection to express it. That
  token layer collapsed to pass-throughs to system colours the moment True Black
  went (41 lines of `Theme.swift` deleted, 50 call sites simplified).
- **Why not**: it is a theme that means "turn off the thing we just adopted".
  Retiring it removes a user-facing option, so the persisted selection is
  migrated rather than dropped: `AppTheme.init(from:)` maps the stored
  `"trueBlack"` raw value onto `.dark`. Without that mapping
  `@UserDefaultsBacked` would fail to decode and silently reset the user to
  System, discarding their dark-mode choice along with the OLED preference.

### Alternative 3: Adopt `UITabBarController.Mode.tabSidebar` on iPad

- **Pros**: it is the system-blessed iPadOS 18+ navigation pattern, it is where
  Apple's design direction points, and it would surface tab hierarchy without
  Spud building its own sidebar.
- **Cons**: it collides with the split view Spud already has.
- **Why not**: **observed, then explained by Apple's own API.** In a spike
  (rejected and reverted with no commit), with the sidebar shown the system tab
  sidebar rendered as a dimmed/blurred overlay directly on top of the Posts
  tab's own primary column, with the vote controls faded underneath — a literal
  sidebar-over-sidebar collision.

  That is not a bug to work around; it is the documented default.
  `UITabBarControllerSidebar.Layout` (`preferredLayout`, default `.automatic`,
  which "on iOS ... resolves to `overlap`") offers exactly two shapes:
  `.overlap` — "When the sidebar is displayed, it will overlap the selected view
  controller, allowing the selected view controller to render underneath the
  sidebar" — and `.tile` — "the selected view controller is resized and shifted
  to display alongside the sidebar. The selected view controller is not occluded
  by the sidebar". This is the **same dichotomy** as `UISplitViewController`'s
  `.overlay` / `.tile` split behaviours, not an analogy: the same overlap-versus-
  reflow choice, one container level up.

  Spud already made that choice one level down and made it deliberately —
  `MainWindowSplitViewController` uses `preferredSplitBehavior = .tile`
  specifically so both columns stay visible and interactive. Accepting an
  overlapping sidebar above a tiled split is accepting the trade the tiled split
  was chosen to avoid.

  **The portrait toggle is not a dev-only artefact.** The spike forced
  `sidebar.isHidden = false` in portrait to observe the collision, but Apple
  documents that "by default, the system presents the sidebar in landscape
  orientation and hides it in portrait orientation; however, **people can toggle
  between the tab bar and sidebar in either orientation**". So the spike
  reproduced a state any user can reach in one tap. That strengthens the
  rejection rather than weakening it.

  **Explicitly scoped out, not overlooked**: landscape — the orientation where
  Apple documents the sidebar as visible by default — was never observed, and an
  explicit `sidebar.preferredLayout = .tile` override was never tried as a
  mitigation. Neither was needed to reach REJECT, because the portrait toggle
  alone is a one-tap regression today's layout never suffers.

## Consequences

### Positive

- Bars, sheets, popovers, and floating chrome are system Liquid Glass, so Spud
  inherits future refinements to the material instead of re-implementing them.
- Net deletion: 28 lines of bar-appearance overrides, the `Theme` token layer,
  custom sheet/popover backgrounds, and the Dark/True-Black same-style re-resolve
  nudge in `MainWindow.applyTheme` (unnecessary once each remaining theme maps to
  a distinct `UIUserInterfaceStyle`).
- The theme picker got simpler and more honest — three appearances that each map
  onto a real `UIUserInterfaceStyle`, with no "this one also repaints your
  backgrounds" special case.
- Search became a `UISearchTab`, which the system positions and localises itself
  (and separates from the other tabs in a compact tab bar).
- The iPad split view keeps both columns usable, which is what a tab sidebar
  would have taken away.

### Negative

- **The deployment floor is iOS 26.0**, up from 18.0. Anyone below that cannot
  run the app at all. This is the real cost of the decision.
- True Black users lose a feature. They land on Dark, not on their own choice.
- Content now scrolls beneath translucent bars, which means every scrolling
  screen has to pin to `view.topAnchor` rather than the safe area and let content
  inset adjustment do the resting. Five screens needed repinning; a sixth was
  deliberately left alone because its content is an inset rounded card, not
  full-bleed scroll content.
- `UIGlassEffect` tints from the inherited trait rather than the backdrop, unlike
  the locked-dark blurs it replaces, so surfaces with fixed-white content need an
  explicit trait pin on an ancestor view. See the "Appearance and Liquid Glass"
  section of `CLAUDE.md` for the observation table.

### Risks

- **Snapshot coverage of glass is thinner than the green suite suggests.** Five
  screen classes (`LoginScreen`, `Register`, `ForgotPassword`, `LoginTwoFactor`,
  `OnboardingHomeBase`) wrap real navigation controllers but render offscreen,
  which never composites the glass material — they structurally cannot catch a
  glass regression, and they passed unchanged only because the old flat fill and
  the new transparent reveal happen to produce identical pixels there. The six
  buttons converted to glass configurations have no automated visual coverage at
  all. Do not read "the snapshot plan is green" as "glass is verified".
- **Ad hoc on-screen key-window tests corrupt later snapshot captures for the
  rest of the simulator boot**, producing convincing false failures (and, worse,
  false passes). This cost this initiative time four separate times. Mitigation
  and the visible-but-never-key escape hatch are documented in
  `SpudSnapshotTests/CLAUDE.md`.
- Some accessibility verification is owed rather than done: an Increase Contrast
  per-surface capture was never taken, and Reduce Transparency could not be
  live-toggled on iOS 26.3.1 (a static audit of every `UIVisualEffectView` site
  was substituted — all six use the adaptive `system*Material*` family).

### Related ruling: `UIBackgroundExtensionView` is kept despite having no payoff today

Banner headers wrap their image in a `UIBackgroundExtensionView` so it reads as
continuing beneath an adjacent iPad sidebar. **It currently has no visible
effect**, because `MainWindowSplitViewController` uses
`preferredSplitBehavior = .tile`, which is structurally incompatible: tiling
means zero column overlap, so there is no region to extend into.

Switching to `.overlay` / `.displace` to make it pay off was rejected. Apple
documents the overlay display mode (`.oneOverSecondary`, the mode `.overlay`
enables) as leaving the secondary view controller "dimmed out, preventing
interaction with its view" — which would wreck the both-columns-usable iPad
layout this codebase already invested in. That trade is a separate product
decision, not this initiative's to make.

The code stays because it is correct, cheap, and becomes visible the day the
split behaviour changes. One caveat is load-bearing: it sets
`automaticallyPlacesContentView = false` and pins the content view to the safe
area itself. That is a workaround, not a style choice — with the automatic
default, hosting the view inside a table header sized via
`systemLayoutSizeFitting` reliably **hung the app**.

## When to revisit

- **The iOS 26 floor**: only if Spud needs to ship to a user base still below
  iOS 26 — which means re-adding, not un-deleting, the appearance code. Nothing
  else reopens the floor.
- **True Black**: only if Apple ships a supported way to express a pure-black
  appearance that does not require suppressing the system bar material. "OLED
  users want it" is not a reason on its own; that was true when it was retired.
- **The tab sidebar**: if Spud's iPad navigation is redesigned such that the
  Posts tab no longer owns a primary column (removing the collision), or if
  Apple changes the `.automatic` layout resolution on iOS. A `preferredLayout =
  .tile` override was never tried and would be the first thing to test if this is
  reopened — but only after the collision itself is gone, because a tiled system
  sidebar plus a tiled app split view is two sidebars competing for the same
  leading edge.
