# Collapsed-parent "N new" badge + reachable jumps (post detail)

Date: 2026-06-16
Status: Design approved, ready for implementation plan

## Problem

The new-comment treatment (gutter dot, fade wash, banner, jump FAB) counts new
comments **tree-wide**: `PostDetailViewModel.newCommentCount` includes comments
hidden under a collapsed parent. This produces two gaps when a user has collapsed
a thread that contains new replies:

1. **No signpost.** A collapsed parent shows only its total hidden-descendant
   count (`"+N"`); nothing indicates that some of those hidden replies are new, so
   the new comments are invisible and unreachable by eye.
2. **Dead jumps.** The banner reads "N new since your last visit" with a "Jump"
   action, and the FAB offers "Next new". When the target new comment is collapsed
   away it has no index path, so `jumpToFirstNewComment()` silently **no-ops** and
   the FAB **skips** it. The banner's count then over-promises what the controls
   can deliver.

This is the one real functional gap left in the post-tracking initiative. The fix
is driven by the Spud Comment-States design
(`~/Downloads/spud/project/comment-states.jsx`, the fresh-collapsed demo): a
collapsed parent renders its own accent **"N new"** pill beside the `"+N"` count
(demo node `glidergun`: hiddenCount 22, newCount 5 → "+22" · "5 new"; node
`sysadmin_sam`: newCount 0 → "+8" only).

## Decisions (confirmed)

- **Show an accent "N new" pill on every collapsed-and-visible parent that hides
  ≥1 new descendant**, beside the existing `"+N"` total-hidden count. Absent when
  the new count is 0. Counts nested-collapsed new descendants too (same semantics
  as the existing total count).
- **Auto-expand then jump.** When the banner "Jump" or the FAB "Next new" targets a
  new comment that is collapsed away, expand the collapsing ancestor(s) so the
  control lands on the **actual** new comment. Jumps never no-op and never silently
  skip a hidden-new comment.
- **FAB ordering uses an anchor row.** A new comment's scroll position for "is there
  a next new below the fold" is the comment itself when visible, else its nearest
  visible collapsed ancestor. A hidden-new comment therefore still counts as a jump
  target and keeps the FAB styled "Next new".
- **Rebuild without animation, then scroll.** The expand re-applies the diffable
  snapshot non-animated, then `scrollToRow` (animated unless reduce-motion is on),
  to avoid a janky insert-then-scroll and reliably land on the target.
- **Pill styling = the new-comment accent.** Teal fill, bold monospaced digits,
  rounded — the same pill shape as the author role badges, tinted with the
  new-comment teal rather than a role color. Distinct from the quiet
  secondary-label `"+N"` text.
- **No localization work** — Spud is English-only; `NSLocalizedString` base values
  ship as-is.

## Current state (from codebase)

- **Collapse computation:** `SpudDataKit/Services/AppDatabase/CommentCollapseState.swift`.
  `visibleTree(orderedComments:collapsedIds:)` returns `VisibleTree(rows,
  collapsedDescendantCounts: [Int64: Int])` in a single pre-order pass that already
  tracks `openCollapsedParents` and accumulates per-parent hidden counts. Also has
  `descendantIds(of:in:)`. Pure, UIKit-free, fully unit-tested in
  `CommentCollapseStateTests`.
- **View model:** `PostDetailViewModel` holds `orderedComments`, `collapsedElementIds`,
  `newCommentState: NewCommentState.Result` (`newElementIds: Set<Int64>`,
  `firstNewElementId`, `count`), and exposes `visibleCommentTree()`,
  `isNewComment(elementId:)`, `newCommentCount`, `firstNewCommentElementId`,
  `orderedNewCommentElementIds`, `toggleCollapse(elementId:)`.
- **Cell view model:** `PostDetailCommentViewModel` takes `collapsedDescendantCount:
  Int?` → renders `collapsedBadgeText` (`"+N"`) and `isNew: Bool` → drives the dot/
  wash. Already assembles the role-badge pills via the cell's `makeBadgeView`.
- **Cell:** `PostDetailCommentCell` has a trailing metadata stack containing
  `badgesStackView` and `collapsedBadgeLabel` (the `"+N"` label,
  `accessibilityIdentifier = "collapsedBadge"`).
- **Host VC:** `PostDetailViewController` stores `collapsedDescendantCounts` (set
  from `visibleCommentTree()` in the snapshot build at ~L431), passes
  `collapsedDescendantCount` + `isNew` into the cell VM at construction (~L1492),
  and implements the banner (`jumpToFirstNewComment`), the FAB
  (`indexPathOfNextNewComment` / `jumpTarget` / `jumpToNextTopCommentTapped` /
  `updateJumpButtonVisibility` / `applyJumpButtonStyle`).

## Design

### Component 1 — `CommentCollapseState` (pure, SpudDataKit)

- Add `newElementIds: Set<Int64> = []` parameter to `visibleTree(...)`. Extend
  `VisibleTree` with `collapsedNewDescendantCounts: [Int64: Int]`. In the existing
  loop, alongside `collapsedCounts[parent.id] += 1`, increment a parallel
  `collapsedNewCounts[parent.id]` only when `newElementIds.contains(row.id)`. A
  parent absent from the dictionary (or value 0) means no hidden-new descendants.
  Default empty `newElementIds` preserves current callers/tests.
- Add `collapsedAncestors(of elementId:in orderedComments:collapsedIds:) -> [Int64]`:
  the collapsed ancestor element ids that hide `elementId`. Walk the pre-order list
  backward from `elementId`'s index, tracking the current ancestor depth (each
  strictly-shallower row is the next ancestor); collect those in `collapsedIds`.
  Returns `[]` when the element is visible or not found. Order is leaf→root; the
  caller treats it as a set.

### Component 2 — `PostDetailViewModel`

- `visibleCommentTree()` passes `newCommentState.newElementIds` into `visibleTree`,
  so the VC receives `collapsedNewDescendantCounts`.
- Add `expandAncestors(toReveal elementId:) -> Bool`: compute
  `CommentCollapseState.collapsedAncestors(...)`, subtract them from
  `collapsedElementIds`; return `true` iff the set changed. Idempotent — a
  fully-visible target changes nothing and returns `false`.

### Component 3 — cell view model + cell

- `PostDetailCommentViewModel.init` gains `collapsedNewDescendantCount: Int? = nil`.
  When `> 0`, store a `collapsedNewBadgeText: NSAttributedString?` ("N new"); else
  nil. Extend the collapsed VoiceOver branch to append "N new" after the
  "N hidden" clause (e.g. "collapsed, 22 hidden, 5 new").
- `PostDetailCommentCell` adds a `collapsedNewBadgeLabel` pill (padded, rounded,
  teal fill, bold mono) to the trailing metadata stack, immediately after
  `collapsedBadgeLabel`. `accessibilityIdentifier = "collapsedNewBadge"`. Hidden
  when `collapsedNewBadgeText == nil`; reset in `prepareForReuse`. Teal resolves
  from the same accent the new-comment dot/wash uses.

### Component 4 — `PostDetailViewController` (jump rework)

- Store `collapsedNewDescendantCounts: [Int64: Int]` next to
  `collapsedDescendantCounts`; set both from `visibleCommentTree()`. Pass
  `collapsedNewDescendantCount: collapsedNewDescendantCounts[elementId]` into the
  cell VM at construction.
- **Banner Jump** (`jumpToFirstNewComment`): if `firstNewCommentElementId` resolves
  to no index path, call `viewModel.expandAncestors(toReveal:)`, re-apply the
  snapshot (non-animated), then look up the index path again and `scrollToRow`.
- **FAB next-new** — introduce `anchorIndexPath(forNewComment elementId:)`: the
  element's own index path if visible, else the index path of its nearest visible
  collapsed ancestor (always resolvable; the root is visible). `indexPathOfNextNew`
  iterates `orderedNewCommentElementIds`, using the anchor's `rectForRow().minY` for
  the "below current offset" test, and returns the target element id (not just a
  visible index path). The tap handler expands the target's ancestors if needed,
  rebuilds, then scrolls to the real comment. `jumpTarget` / `updateJumpButtonVisibility`
  use the same anchor test so the FAB shows "Next new" whenever a hidden-new comment
  sits below the fold.

### Data flow

GRDB comment snapshot → `PostDetailViewModel.updateOrderedComments` recomputes
`newCommentState` → VC builds snapshot, calls `visibleCommentTree(newElementIds)` →
`collapsedNewDescendantCounts` flow into cell VMs (pill) and into the jump logic
(via `expandAncestors` / anchor lookup on Jump / Next-new tap).

## Testing

- **`CommentCollapseStateTests`** (pure): `collapsedNewDescendantCounts` for a flat
  collapsed parent (mix of new/old descendants), nested collapses (inner new
  comments count toward every open ancestor), newCount 0 → key absent, no-new tree →
  empty map. `collapsedAncestors`: visible target → `[]`, single collapsed ancestor,
  nested collapsed ancestors (leaf→root chain), unknown id → `[]`.
- **`PostDetailViewModel`**: `visibleCommentTree()` surfaces `collapsedNewDescendantCounts`;
  `expandAncestors(toReveal:)` removes exactly the collapsed ancestors and is
  idempotent (second call returns `false`).
- **Cell VM**: `collapsedNewBadgeText` present iff `collapsedNewDescendantCount > 0`;
  VoiceOver collapsed string includes the "N new" clause.
- **Snapshot** (`PostDetailCommentSnapshotTests`, light + dark): a `test_collapsedWithNew`
  case rendering "+22" + a "5 new" pill, matching the `glidergun` demo node.
- **Jump auto-expand**: the scroll itself is UIKit integration — covered by the
  on-device verification pass, not a unit test. The expand decision is unit-tested
  at the view-model level (`expandAncestors`).

## Out of scope

- The privacy/settings toggle + "Clear history" (separate, deferred item).
- Push notifications (Phase 4, dropped).
- On-device verification of the whole new-comment treatment (separate pass).
