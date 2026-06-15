# Right-edge forward (restore-popped) gesture — Implementation Plan

> Design: see `docs/superpowers/specs/2026-06-15-right-edge-forward-gesture-design.md`.

**Goal:** Right-edge swipe re-pushes the most recently popped view controller (the same
instance), interactively — undoing an accidental Back. Full forward stack, browser-style.

**Architecture:** Two pure, unit-tested units (`InteractiveTransitionGeometry`,
`ForwardStackReducer`) + a `SlidePushAnimator` + a per-nav `ForwardNavigationGestureDriver`
(nav + gesture delegate, holds the forward stack) + a `enableForwardNavigationGesture()`
install seam wired into the app's nav controllers.

## File map

| File | Responsibility |
|---|---|
| `Spud/Utils/Navigation/InteractiveTransitionGeometry.swift` (create) | pure progress/finish math |
| `SpudTests/InteractiveTransitionGeometryTests.swift` (create) | tests for the above |
| `Spud/Utils/Navigation/ForwardStackReducer.swift` (create) | pure forward-stack state machine |
| `SpudTests/ForwardStackReducerTests.swift` (create) | tests for the above (the core) |
| `Spud/Utils/Navigation/SlidePushAnimator.swift` (create) | push animation (incoming from right) |
| `Spud/Utils/Navigation/ForwardNavigationGestureDriver.swift` (create) | gesture + delegate + stack glue |
| `Spud/Utils/Navigation/UINavigationController+ForwardNavigation.swift` (create) | install seam |
| `Spud/Scenes/MainWindow/MainWindowSplitViewController.swift` (modify) | enable on 2 columns |
| `Spud/Scenes/MainWindow/MainWindow.swift` (modify) | enable on 4 tabs + 3 detail navs |

## Conventions

- Swift 6 strict concurrency; new UIKit-facing types `@MainActor`. `SpudTests` is Swift 5 / XCTest.
- Copyright header on every new file. No emojis.
- XcodeGen globs `Spud`/`SpudTests`; run `make project` after adding files.
- `mint run swiftformat <paths>` before staging. `git status -uall`. Stage explicit paths only;
  never `git add -A`; never stage `.remember/remember.md` or `CLAUDE.md`.
- Build: `python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud`
- Unit test a bundle: `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud -only-testing:SpudTests/<Class> -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation -skipMacroValidation test`

## Tasks

1. **`InteractiveTransitionGeometry` (TDD).** `progress(translationX:viewWidth:)` =
   `clamp(-translationX/viewWidth, 0...1)`, zero-width-safe; `shouldFinish(progress:velocityX:)`
   (fling-left finishes, fling-right cancels, else `> 0.5`); constants `completionThreshold = 0.5`,
   `flingVelocity = 800`. Tests: progress {0, half, clamp-1, wrong-direction, zero-width}; shouldFinish
   {past, before, exact-0.5 cancels, fling-left short, fling-right long, exact -800 not a fling}.

2. **`ForwardStackReducer` (TDD — the core).** Pure generic function
   `reduce<Element: AnyObject>(forwardStack:lastStack:newStack:animated:) -> [Element]`:
   - `animated == false` → unchanged.
   - pop (`newStack` strict prefix of `lastStack`) → prepend removed suffix.
   - append push (`lastStack` strict prefix of `newStack`): one added VC `=== forwardStack.first`
     → drop first (consume); else → `[]` (clear).
   - identical stacks → unchanged.
   - else → `[]`.
   Tests (plain `NSObject` instances): single pop prepends; multi-pop prepends in order; restore
   consumes first; new push clears; non-animated keeps; identical (cancelled restore) keeps;
   reshuffle clears.

3. **`SlidePushAnimator`.** Incoming view from `+width` to final (added on top); outgoing view to
   `-width*0.3` with a black dim overlay `0 → 0.15`; Reduce Motion → duration 0; cancel restores
   outgoing frame and removes incoming. Build-verified.

4. **`ForwardNavigationGestureDriver`.** Per spec: right-edge `UIScreenEdgePanGestureRecognizer`,
   `UIPercentDrivenInteractiveTransition`, `forwardStack`/`lastStack`; `didShow` runs the reducer;
   `animationControllerFor` returns `SlidePushAnimator` only when `operation == .push && isInteracting`;
   `interactionControllerFor` returns the interactor; `gestureRecognizerShouldBegin` gates our edge
   pan on `!forwardStack.isEmpty && !isInteracting && transitionCoordinator == nil` and re-vends the
   system left-edge gesture (`count > 1 && transitionCoordinator == nil`). Build-verified.

5. **Install seam + wiring.** `enableForwardNavigationGesture()` (idempotent, associated-object
   retain, `@MainActor`). Wire 9 sites: split view's 2 columns; the 4 tab navs; the 3 regular-width
   detail navs. NOT onboarding/modals. Build + unit tests.

6. **Manual verification** on one booted simulator: tap post → Back → right-edge swipe restores the
   detail at the same scroll position; multi-level (Back twice → two restores); cancel keeps it;
   tapping a new post clears the forward history; left-edge back + Back button still work.

## Self-review checklist

- Reducer rules match the spec table; identity (`===`) used throughout.
- Left-edge back preserved (gesture delegate distinguishes `edgePan` from the system recognizer).
- Custom push animator only during our interaction; everything else system-default.
- `transitionCoordinator == nil` re-entrancy guard present (carried from prior learning).
- No retain cycle (driver weak-refs nav; nav retains driver via associated object).
