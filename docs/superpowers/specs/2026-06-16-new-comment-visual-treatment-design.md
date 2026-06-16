# New-comment visual treatment (post detail)

Date: 2026-06-16
Status: Design approved, ready for implementation plan

## Problem

Phase 1 of the post-tracking initiative computes which comments are new since the
user's last visit to a post (`PostDetailViewModel.newCommentState`:
`isNewComment(elementId:)`, `newCommentCount`, `firstNewCommentElementId`), but
nothing renders it — the data is unused. This adds the visual treatment, driven by
the Spud Comment-States design (`~/Downloads/spud/project/Spud Comment States.html`
/ `comment-states.jsx`): a new comment arrives with a teal background wash that
fades back to the normal background, a persistent marker keeps it identifiable
afterward, a header banner totals the new comments, and a floating pill jumps
between them.

## Decisions (confirmed)

- **Scope: full new-since treatment** — fading wash + persistent gutter dot +
  header banner + "Next new ↓" jump pill.
- **No "NEW" text pill.** The only persistent per-comment marker is a small teal
  gutter dot (the design's "NEW" tag is dropped per review).
- **Fade plays once per comment**, the first time it appears on screen this visit;
  scrolling away and back does not replay it (the dot keeps it marked).
- **Reduced motion** → static teal wash for the visit (no fade); identical dot,
  banner, and pill.
- **Wash color = resolved accent** at 0.16 alpha (dark) / 0.11 (light), not the
  design's fixed `rgb(0,150,135)` — for theme consistency (the app's accent is
  already teal, and `distinguished` already uses `accent.withAlphaComponent`).
- **The web demo's 650ms cross-comment stagger is dropped** — it doesn't map to a
  scrolling list; each comment fades independently on first appearance.
- A comment is "new" relative to `previousVisitAt`, which is fixed for the visit
  (captured at open, before the open is recorded). The set of new comments is
  therefore stable for the visit; on the next visit `lastOpenedAt` has advanced and
  none are new. The fade is a within-visit "settle"; the dot/banner/pill keep them
  identifiable for the rest of the visit.

## Current state (from codebase)

- **Comment cell:** `Spud/Scenes/PostDetail/Content/Comment/PostDetailCommentCell.swift`.
  Has a full-bleed `tintBackingView` already used for the distinguished wash
  (`accent.withAlphaComponent(0.10)`) and the collapsed wash
  (`UIColor.label.withAlphaComponent(0.03)`); reset to `.clear` in
  `prepareForReuse`. `configure(with:imageService:)` resolves `accent = tintColor ?? .systemTeal`
  and sets `tintBackingView.backgroundColor`. Header line is `headerStackView`
  (author + badges + subtitle + spacer + collapsed badge); leading edge is
  `depthRailsView`.
- **Cell view model:** `PostDetailCommentViewModel` (built from `PostDetailCommentRow`).
- **Host VC:** `PostDetailViewController` builds the cell view model, applies a
  diffable snapshot, and already implements `tableView(_:willDisplay:forRowAt:)`
  (added in Phase 3 for seen-capture) and `didEndDisplaying`. It holds
  `commentRowsByElementId` and `viewModel`.
- **Phase 1 data (done):** `PostDetailViewModel.previousVisitAt: Date?`,
  `newCommentState: NewCommentState.Result` (with `newElementIds: Set<Int64>`,
  `firstNewElementId: Int64?`, `count`), `isNewComment(elementId:)`,
  `newCommentCount`, `firstNewCommentElementId`. The comment tree is
  `orderedComments: [PostDetailCommentRow]` (display order, each row has `id`
  = element id and `position`).

## Architecture

### 1. Data plumbing

- `PostDetailCommentViewModel` gains `isNew: Bool`. The VC sets it from
  `viewModel.isNewComment(elementId:)` when building the cell view model.
- `PostDetailViewModel` gains `orderedNewCommentElementIds: [Int64]` — the new
  element ids in display order (filter `orderedComments` by
  `newCommentState.newElementIds`, preserving order). Powers the jump pill.
- A relative-time string for the banner from `previousVisitAt` (e.g. via
  `RelativeDateTimeFormatter`), exposed as `previousVisitRelativeText: String?`.

### 2. Fresh wash + fade (`PostDetailCommentCell` + VC)

- The VC keeps `private var animatedNewCommentIds: Set<Int64> = []` (per visit).
- A pure helper decides the wash for a row:
  `FreshWashState.resolve(isNew:hasAnimated:reduceMotion:) -> FreshWash` where
  `FreshWash` is `.none` / `.fadeFromTint` / `.staticTint`:
  - not new → `.none`
  - new, reduce-motion → `.staticTint`
  - new, motion, already animated → `.none` (dot persists; wash cleared)
  - new, motion, not yet animated → `.fadeFromTint`
- `PostDetailCommentCell.configure` sets the resting wash from `FreshWash`:
  `.staticTint` → `tintBackingView` = accent-tint; `.fadeFromTint` → start at
  accent-tint (so there's no clear-flash before the fade); `.none` → fall through
  to the existing distinguished/collapsed/clear logic. The accent-tint alpha is
  0.16 (dark) / 0.11 (light).
- `PostDetailCommentCell.playFreshFade(restingColor:)` runs a `CAKeyframeAnimation`
  on `tintBackingView.layer.backgroundColor`: keyTimes `[0, 0.38, 1.0]`, values
  `[tint, tint, restingColor]`, duration `4.2`, `easeOut`; sets the model layer to
  `restingColor` so it sticks. `restingColor` is the row's non-fresh resting tint
  (clear, or the distinguished/collapsed tint if the comment is also in that state)
  — so the fade never erases another state.
- In `tableView(_:willDisplay:forRowAt:)` (the existing Phase 3 hook): for a `.post`
  row, if `isNew` and the id is not in `animatedNewCommentIds` and motion is allowed
  (`!UIAccessibility.isReduceMotionEnabled`), insert the id and call
  `cell.playFreshFade(restingColor:)`. (Insert before animating so a second
  `willDisplay` can't double-trigger.)

### 3. Persistent gutter dot

- `PostDetailCommentCell` gains a small (~7pt) teal/accent dot view at the leading
  edge of the header line, shown when `viewModel.isNew`, hidden otherwise. Reset in
  `prepareForReuse`. It persists regardless of wash/fade state, so a new comment
  stays identifiable for the visit after the wash clears.

### 4. Header banner (in-flow)

- When `newCommentCount > 0`, an accent-tinted band appears at the top of the
  comment list (a dedicated row/section above the first comment, scrolling with
  content): a teal dot + "**N new** since your last visit · {relative time}" + a
  trailing "Jump ⌄" control. "Jump" scrolls to `firstNewCommentElementId`.
- Implemented as its own diffable item/section so it inserts/removes cleanly and
  hides when there are no new comments.

### 5. "Next new ↓" floating pill

- An accent pill button pinned bottom-right of the comment list, shown only while at
  least one new comment sits below the current viewport. Tapping scrolls to the next
  new comment past the current top-visible row, cycling through
  `orderedNewCommentElementIds`.
- The selection logic is a pure helper:
  `NextNewComment.next(after currentTopElementId:, in orderedNewIds:, allVisibleOrder:) -> Int64?`
  (given the current scroll anchor and the ordered new ids, return the next new id,
  wrapping). Visibility/scroll wiring is the thin UIKit part (compute the top-visible
  index path, map to element id, scroll to the returned id's index path).

### 6. Accessibility & reduced motion

- A new comment's cell adds VoiceOver context: "New comment, posted after your last
  visit." (the gutter dot is decorative — `isAccessibilityElement = false`).
- Reduced motion: static wash (no animation); dot, banner, and pill unchanged.
- Banner and pill are accessible controls with labels; Dynamic Type via existing
  label styles.

## Testing

- **Pure, unit-tested:**
  - `FreshWashState.resolve(isNew:hasAnimated:reduceMotion:)` — the 4 cases above.
  - `NextNewComment.next(...)` — next-after-anchor, wrap-around, none-when-empty,
    anchor-is-last.
  - `orderedNewCommentElementIds` ordering (display order, only new ids).
- **Snapshot:** add a "fresh comment" case to `PostDetailCommentSnapshotTests`
  covering the static end-states — tinted-with-dot and faded-with-dot (clear bg +
  dot). The fade animation timing itself is not unit-tested (UIKit/Core Animation).
- Existing `NewCommentState` tests already cover which comments are new.

## Out of scope / deferred

- No "NEW" text pill (dropped).
- No change to how "new" is computed (Phase 1 owns that).
- Collapsed-parent "N new" count badge (the design shows it; deferrable — the
  banner already totals new comments). Include only if it falls out cheaply;
  otherwise a follow-up.
- Push notifications (separate, dropped earlier).
