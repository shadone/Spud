# Undo accidental scroll-to-top — design

Date: 2026-06-23
Status: Approved (pending implementation plan)
Scope: `PostListViewController` + a small interactive extension to `ToastPresenter`,
plus one new reusable cell-pulse helper. No view-model or data-layer changes.

## Problem

Tapping the iOS status bar scrolls the active scroll view to the top. In the post
list this is frequently *accidental* — a status-bar tap meant for something else,
or a mis-tap near the top of the screen — and when you're reading deep in the feed
it throws away your place with no way back. We want to detect the accidental jump
and offer a one-tap undo that restores you exactly where you were.

## What exists today

- **No scroll-to-top handling.** `PostListViewController`
  (`Spud/Scenes/PostList/PostListViewController.swift`) is a `.plain`
  `UITableView` backed by a `UITableViewDiffableDataSource<Section, Item>`
  (sections `.posts` / `.loading`). It implements `scrollViewDidScroll(_:)`
  (pagination trigger, ~`:1416`), `willDisplay` / `didEndDisplaying` (read
  tracking), and `didSelectRowAt`. It does **not** implement
  `scrollViewShouldScrollToTop(_:)` or `scrollViewDidScrollToTop(_:)`, and has no
  `scrollViewWillBeginDragging(_:)`. These are clean hooks.
- **`ToastPresenter`** (`Spud/Scenes/Common/Toast/ToastPresenter.swift`) — a
  `@MainActor` singleton with `func show(_ message: String, in window: UIWindow)`
  (`:36`). It is **text-only, non-interactive** (`ToastView.isUserInteractionEnabled
  = false`, `:111`), **auto-dismisses after 2s** (`:81`), and **coalesces** —
  calling `show` again updates the text and resets the timer (`:37`). Styling
  (`ToastView`, `:96`): `.secondarySystemBackground` pill, corner radius 20, 16/10
  padding, centered 24pt above the safe-area bottom. There is **no** action-button
  affordance and **no** transient-undo pattern anywhere in the app yet.
- **Theme tokens.** `ThemeManager.currentAccentColor` (SpudUIKit) is the accent
  used for prominent buttons elsewhere in this controller
  (`makeErrorConfiguration`, ~`:894`).

## Interaction model (approved)

A status-bar tap that scrolls you up from deep in the feed shows an **ephemeral
undo toast**. The toast is only a *hint* — the undo capability itself lives in
controller state and outlives the toast. Two ways to undo, both identical in
effect:

1. **Tap "Undo"** on the toast.
2. **Tap the status bar again** while still at the top — a *toggle*. Because you're
   already at the top, iOS has nothing to scroll, so `scrollViewDidScrollToTop`
   does not fire; we intercept the re-tap in `scrollViewShouldScrollToTop` and
   perform the undo there. This reuses the muscle memory the gesture already has
   and works even after the toast has expired (until you manually scroll).

**Restore is an instant snap** (no animated scroll — the distance can be huge and
an animated restore is either sluggish or snaps anyway), immediately followed by a
**brief pulse** of the row you were reading and a short **confirmation toast**.

### Decisions

1. **Offer undo only when scrolled deep.** Arm the undo only if the pre-jump offset
   was past ~one screen height (`tableView.bounds.height`). A small tap-to-top near
   the top is trivially re-scrollable, so we stay silent and avoid toast noise.
2. **Toggle re-tap performs the undo directly** (not "re-show the toast then tap
   Undo"). Fewer taps; the toast taught the gesture the first time.
3. **Instant snap restore**, `setContentOffset(_:animated:false)`.
4. **Pulse the anchored row on every restore** (both undo paths) — a brief
   accent-tinted background flash, ~0.6s ease-out, self-removing. It's an opacity
   fade, not motion, so it stays on under Reduce Motion (shortened/skipped per that
   setting).
5. **Confirmation toast on both undo paths** — `"Back to where you were."`, the
   plain text (non-interactive) toast, ~2s. On the button path it reads as a
   sequence (`"Jumped to top · Undo"` → tap → `"Back to where you were."`); on the
   silent toggle path it explains what the gesture just did.
6. **State outlives the toast.** The undo capability is held in
   `pendingScrollUndo`, independent of toast lifetime — so the toggle still works
   after the hint toast auto-expires, and an unrelated toast (e.g. a refresh
   failure) replacing ours never disables undo.
7. **Programmatic scrolls never trigger it.** `setContentOffset` does not fire
   `scrollViewDidScrollToTop`, so app-driven scroll-to-top (and our own restore)
   can't produce a false undo toast.
8. **Post-list scope only.** This controller is shared by frontpage / community /
   saved feeds, so all of them get the behavior. Other scroll views (post detail,
   inbox, profile) are out of scope for v1.

## State

```swift
private struct PendingScrollUndo {
    let offset: CGPoint   // exact contentOffset to restore
    let anchorItem: Item  // diffable data-source id of the topmost substantially-visible
                          // post at capture time — the row to pulse on restore
}

// Armed on a deep status-bar scroll-to-top; cleared on undo or invalidation.
private var pendingScrollUndo: PendingScrollUndo?

// Captured in shouldScrollToTop (before the jump), promoted to pendingScrollUndo in
// didScrollToTop only if it was deep enough.
private var candidateScrollUndo: PendingScrollUndo?
```

"Topmost substantially-visible post" = the first `indexPathsForVisibleRows` entry
in the `.posts` section whose cell is meaningfully on screen (its bottom below the
content-inset top edge), mapped to its identifier via
`dataSource.itemIdentifier(for:)`. If none resolves (e.g. only the loading section
is visible), no anchor is captured and the feature no-ops for that tap.

## Behavior (state machine)

```
status-bar tap
   │
   ▼
scrollViewShouldScrollToTop
   ├─ pendingScrollUndo != nil  ──▶  TOGGLE: performScrollUndo(); return false
   │                                  (already at top, nothing to scroll)
   └─ pendingScrollUndo == nil  ──▶  candidateScrollUndo =
                                       (contentOffset, topmost-visible item)
                                      return true   (let iOS scroll to top)
                                          │
                                          ▼
                              scrollViewDidScrollToTop   (fires only on real scroll)
                                 candidate.offset.y >= bounds.height ?
                                   ├─ yes ▶ pendingScrollUndo = candidate
                                   │        show undo toast ("Jumped to top" + Undo)
                                   └─ no  ▶ stay silent
                                 candidateScrollUndo = nil

Undo  (toast "Undo" button  OR  toggle re-tap)  ─▶ performScrollUndo()

performScrollUndo():
   guard let pending = pendingScrollUndo
   tableView.setContentOffset(pending.offset, animated: false)   // instant snap
   pendingScrollUndo = nil
   dismiss undo toast
   pulse(anchorItem: pending.anchorItem)                         // brief flash
   ToastPresenter.shared.show("Back to where you were", in: window)   // confirm

Invalidate (pendingScrollUndo = nil, dismiss undo toast) on:
   • scrollViewWillBeginDragging   (user manually scrolled — moved on)
   • pull-to-refresh / reloadFeed
   • feedChanged()                 (feed key swap; saved offset/anchor now stale)
```

`scrollViewWillBeginDragging` only fires for user touch-drags, not for the
programmatic scroll-to-top animation or our `animated: false` restore, so wiring
invalidation there does not fight the feature.

## Changes

### `ToastPresenter` — interactive variant

Add an overload alongside the existing text-only `show(_:in:)` (which is untouched
and still used for refresh-failure / outbox toasts and our confirmation toast):

```swift
func show(_ message: String,
          actionTitle: String,
          in window: UIWindow,
          duration: Duration = .seconds(4),
          action: @escaping @MainActor () -> Void)
```

- `ToastView` gains an optional trailing button (system `UIButton`, accent
  `ThemeManager.currentAccentColor`, title = `actionTitle`). When an action is
  present the toast is interactive; the existing non-action path keeps
  `isUserInteractionEnabled = false`.
- **Hit-testing**: the toast's host overlay must pass touches through everywhere
  *except* the toast pill's own bounds, so the "Undo" button is tappable while the
  feed underneath stays fully usable. (The non-interactive toast already lets
  touches through by being `isUserInteractionEnabled = false`; the interactive one
  needs an overlay whose `hitTest` returns the button only inside the pill and
  `nil` elsewhere.)
- Tapping the action invokes `action()` then dismisses immediately. Auto-dismiss
  uses `duration` (default 4s for the undo hint vs the 2s text default).
- Coalescing is unchanged; the undo toast can still be superseded by a later toast
  without affecting `pendingScrollUndo`.

### `PostListViewController`

1. **`scrollViewShouldScrollToTop(_:) -> Bool`** — the toggle/capture intercept per
   the state machine. Returns `false` to consume the re-tap when undoing, `true`
   otherwise.
2. **`scrollViewDidScrollToTop(_:)`** — promote `candidateScrollUndo` to
   `pendingScrollUndo` and show the undo toast when the pre-jump offset was deep
   enough; otherwise stay silent. Clears `candidateScrollUndo`.
3. **`scrollViewWillBeginDragging(_:)`** — new; invalidate `pendingScrollUndo` +
   dismiss the undo toast.
4. **`performScrollUndo()`** — instant snap, clear state, dismiss toast, pulse,
   confirmation toast (per the state machine).
5. **Undo toast call site** — `showUndoScrollToast()` calling the new interactive
   `ToastPresenter` overload with title `"Jumped to top"`, action title `"Undo"`,
   action `{ [weak self] in self?.performScrollUndo() }`, guarded on `view.window`.
6. **Invalidation wiring** — call the invalidation in the existing `feedChanged()`
   and the pull-to-refresh `refreshTriggered()` paths (alongside their current
   teardown), so a feed swap never restores into a stale list.

### New reusable cell-pulse helper

A small `UITableViewCell` (or `UIView`) extension in the **app target**,
`Spud/Scenes/Common/`:

```swift
func pulseHighlight(color: UIColor = ThemeManager.currentAccentColor)
```

Adds a self-removing overlay (or animates `backgroundColor`) at low alpha, fades
out ~0.6s ease-out, honoring `UIAccessibility.isReduceMotionEnabled` (shorter/no
animation, still a brief static tint). Kept out of the controller so the flash is
isolated and independently testable. The controller resolves
`dataSource.indexPath(for: anchorItem)` → `cellForRow(at:)` and calls it; if the
anchor row isn't currently realized the pulse is simply skipped (restore still
happened).

## Edge cases

- **Anchor row gone after restore** — feed changes already invalidate
  `pendingScrollUndo`, so `performScrollUndo` only runs against a live feed. If the
  specific cell still isn't realized at the restored offset, the pulse is skipped;
  the snap-back itself is unaffected.
- **Shallow tap-to-top** — below the one-screen threshold: normal scroll-to-top,
  no toast, no armed undo. The status bar behaves exactly as today.
- **Re-tap after manual scroll** — manual drag cleared `pendingScrollUndo`, so the
  next status-bar tap is a normal scroll-to-top that re-captures a fresh candidate.
- **Undo toast superseded** — a refresh-failure toast can replace the undo hint;
  the toggle still works because `pendingScrollUndo` is independent of the toast.
- **VoiceOver** — the status-bar tap isn't a VoiceOver gesture, so the toast's
  "Undo" button is the accessible path. Post a `.announcement` /
  `.layoutChanged` notification when the undo toast appears and give the button a
  clear label/trait. (Toggle-by-status-bar is simply unavailable under VoiceOver,
  which is fine — the button covers it.)

## Testing

- **Decision logic** — factor the "should I arm / toggle / invalidate" choices into
  small pure helpers (e.g. `shouldArmUndo(forOffset:viewportHeight:) -> Bool`,
  and the candidate→pending promotion) and unit-test them: deep offset arms, shallow
  does not; pending-set routes a re-tap to undo; drag/refresh/feed-change clear it.
- **Pulse trigger** — assert `performScrollUndo` resolves the anchor item to an
  index path and requests a pulse (inject/spy the pulse call), rather than
  snapshotting a mid-flight animation.
- **Toast snapshots** — static light/dark snapshots of `ToastView` in both forms:
  text-only ("Back to where you were") and with the trailing "Undo" button. Add to
  the existing `SpudSnapshots` plan (iPhone 14 Pro / portrait).
- **Manual simulator check** — scroll deep, tap the status bar: "Jumped to top ·
  Undo" appears; tap Undo → instant snap back, row pulses, "Back to where you were"
  confirms. Repeat and instead tap the status bar a second time → same undo +
  confirm. Let the toast expire, then tap the status bar → still undoes. Manually
  scroll during the window → toast gone, next status-bar tap scrolls to top fresh.
  Shallow scroll + status-bar tap → no toast.

## Out of scope (v1)

- Any other scroll view (post detail, inbox, person profile, search).
- A user setting to disable the behavior.
- Haptics on undo (could add a light impact later).
- Persisting the undo position across feed reloads or app backgrounding — the
  capability is intentionally session-local and invalidated by feed changes.
