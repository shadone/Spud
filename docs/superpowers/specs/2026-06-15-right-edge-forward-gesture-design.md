# Right-edge interactive forward (restore-popped) gesture

Date: 2026-06-15
Status: Design approved, implementing

## Problem

The left-edge back swipe is easy to trigger by accident, popping a screen the user
didn't mean to leave. There is no quick way to undo that. We want a **forward**
gesture: swipe from the **right** edge to re-push the screen you just popped —
restoring the *same* instance (and its scroll position / expanded comments), like
Safari's forward-edge swipe.

Example:
1. Post list → tap a post → post detail pushed.
2. Press Back (or left-edge swipe) → detail popped → back on the post list.
3. "Oops, I wanted that detail." Swipe from the right edge → the same detail is
   re-pushed. Back where you were.

This is the inverse of an earlier misread (which built the right edge as a second
*back* gesture). That work is discarded; this replaces it.

## Decisions (confirmed)

- **Left edge unchanged.** The system left-edge back gesture and the Back button keep
  working exactly as today (accidents still happen — the right edge is the undo).
- **Right edge = forward**, restoring popped view controllers.
- **Full forward stack.** Consecutive backs are all remembered; each right-edge swipe
  restores one level, browser-style.
- **Interactive.** The restored screen tracks the finger from the right edge and can
  be cancelled mid-swipe.
- **Public API only** (custom `UIViewControllerAnimatedTransitioning` +
  `UIPercentDrivenInteractiveTransition` + `UIScreenEdgePanGestureRecognizer`), no
  private selectors — App Store safe.

## Current state (from codebase)

- Navigation is UIKit: `UINavigationController`s inside a `UISplitViewController` (Posts
  tab). On iPhone (compact) the split view is collapsed; tapping a post does
  `postListNavigationController.pushViewController(_:animated: true)` (`MainWindow.pushDetail`).
- No nav controller currently sets a `UINavigationControllerDelegate` (we are the first).
- Post detail and post-list cells use a custom `SwipeActionView` (horizontal pan,
  swipe-to-vote). The system left-edge gesture already wins over it at the edge.
- Split-view collapse/expand moves VCs between columns via
  `setViewControllers(_:animated: false)` — i.e. **non-animated** structural changes.
- Swift 6.0, strict concurrency complete, iOS 18. New types are `@MainActor`.

## Architecture

Four small units; the subtle logic is isolated into a pure, unit-tested reducer.

### 1. `InteractiveTransitionGeometry` (pure)

UIKit-free math, unit-tested:
- `progress(translationX:viewWidth:)` → `clamp(-translationX / viewWidth, 0...1)` (the
  right-edge gesture drags leftwards, so negative translation increases progress).
- `shouldFinish(progress:velocityX:)` → fling left finishes, fling right cancels,
  else past the halfway threshold.
- Constants `completionThreshold = 0.5`, `flingVelocity = 800`.

### 2. `ForwardStackReducer` (pure, the core — unit-tested)

A single pure function decides how the per-nav forward stack evolves on each
navigation transition, given the previous and current stacks. Generic over
`AnyObject` so it is tested with plain objects, no UIKit:

```
reduce(forwardStack, lastStack, newStack, animated) -> newForwardStack
```

Rules:
- `animated == false` → return `forwardStack` unchanged. (Ignores the split-view
  `setViewControllers(animated:false)` column handoffs and other structural changes,
  so they never pollute the stack.)
- **Pop** (`newStack` is a strict prefix of `lastStack`): prepend the removed
  suffix to the forward stack (nearest-ahead first). Handles single and multi-level
  pops (e.g. pop-to-root).
- **Append push** (`lastStack` is a strict prefix of `newStack`):
  - exactly one VC added and it `===` `forwardStack.first` → that was our restore;
    drop the first element (consume).
  - otherwise → genuinely new navigation; clear the forward stack (browser semantics).
- **No net change** (equal stacks by identity) → unchanged. (A cancelled interactive
  restore nets to no change.)
- **Anything else** (reshuffle / wholesale replace) → clear (conservative).

### 3. `SlidePushAnimator`

`UIViewControllerAnimatedTransitioning` for a push: the incoming (restored) view
slides in from the right following the finger; the outgoing view slides left with a
slight parallax and a dim overlay that fades in. Honors Reduce Motion (instant cut).
On cancel: restore the outgoing view's frame, remove the incoming view.

### 4. `ForwardNavigationGestureDriver`

`@MainActor` `NSObject`, attached per nav controller; conforms to
`UINavigationControllerDelegate` and `UIGestureRecognizerDelegate`. Holds:
`forwardStack: [UIViewController]`, `lastStack: [UIViewController]`, an optional
`UIPercentDrivenInteractiveTransition`, an `isInteracting` flag, and a right-edge
`UIScreenEdgePanGestureRecognizer`.

- **init:** snapshot `lastStack = nav.viewControllers`; add the right-edge pan to
  `nav.view`; `assert(nav.delegate == nil)`, set `nav.delegate = self`; set
  `nav.interactivePopGestureRecognizer?.delegate = self` (so assigning a nav delegate
  doesn't disable the system left-edge back gesture — we re-vend its shouldBegin).
- **`didShow`:** `forwardStack = ForwardStackReducer.reduce(forwardStack, lastStack,
  nav.viewControllers, animated)`; then `lastStack = nav.viewControllers`.
- **`animationControllerFor operation:`** returns `SlidePushAnimator()` only when
  `operation == .push && isInteracting`; else `nil` (back-button, left-edge,
  programmatic, normal pushes all keep the system default).
- **`interactionControllerFor:`** returns the interactor (non-nil only during our
  right-edge gesture).
- **`gestureRecognizerShouldBegin`:** for our edge pan → `!forwardStack.isEmpty &&
  !isInteracting && nav.transitionCoordinator == nil`; for the system
  `interactivePopGestureRecognizer` (identified by `===`) → `nav.viewControllers.count
  > 1 && nav.transitionCoordinator == nil` (preserves left-edge back).
- **pan handler:** `.began` (forward stack non-empty) → `isInteracting = true`, create
  interactor, `pushViewController(forwardStack.first!, animated: true)`. `.changed` →
  `interactor.update(progress)`. `.ended` → finish or cancel by
  `shouldFinish(progress:velocityX:)`, then clear `isInteracting`/interactor.
  `.cancelled/.failed` → cancel, clear. The forward stack is mutated only by the
  reducer in `didShow` — finish nets an append-push (consumed), cancel nets no change
  (kept).

### 5. Install seam

`UINavigationController.enableForwardNavigationGesture()` — idempotent extension that
constructs a driver and retains it via associated object. Called at the same nav
controller creation sites as before: the split view's two columns, the four tab nav
controllers, and the regular-width detail nav controllers. (Onboarding and modals are
out of scope.)

## Behavior summary

| Event | Forward stack effect |
|---|---|
| Back button / left-edge swipe / programmatic pop (animated) | popped VC(s) prepended |
| Tap into a new screen (animated push) | cleared |
| Right-edge swipe completed | top consumed (re-pushed) |
| Right-edge swipe cancelled | unchanged (VC stays) |
| Split-view column handoff (`setViewControllers animated:false`) | unchanged (ignored) |
| Forward stack empty | right-edge gesture inert |

## Edge cases & risks

- **Restoring the same instance** preserves scroll/expanded state. Risk: a popped
  `PostDetailViewController` must resume its data observation on re-appear. Verify
  during implementation; fix if it doesn't refresh.
- **Memory:** retained popped VCs are held until restored or cleared (cleared on any
  new navigation). Deep accidental back-chains are rare; no hard cap for v1.
- **iPad / regular width:** tapping a post replaces the detail column rather than
  pushing, so the forward gesture mainly applies to the compact (iPhone) push/pop
  flow; installing on the detail navs is harmless.
- **Reduce Motion:** animator collapses to an instant cut.

## Testing

- Unit tests for `InteractiveTransitionGeometry` (progress, shouldFinish, boundaries)
  and for `ForwardStackReducer` (pop, multi-pop, restore-consume, new-push clear,
  non-animated ignore, no-net-change keep, reshuffle clear). The reducer is the
  highest-value target and is fully testable without UIKit.
- The animator, driver glue, and gesture feel are verified manually on a simulator
  (gesture automation is unreliable in this repo).

## Out of scope

- Changing the left-edge gesture or Back button.
- A persistent/cross-launch forward history.
- Forward gesture on onboarding or modal navigation controllers.
