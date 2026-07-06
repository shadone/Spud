# Comment Inline-Image Zoom Glitch Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An inline body image finishing its async load never animates its host row's re-measure — the comment cell and DM bubble rows snap to their new height exactly like the post header does, killing the "image zooms from a corner" glitch. The three existing per-host variants of "re-measure without animation" consolidate into one named `UITableView` helper.

**Root cause (verified, 2026-07-06 scout):** when an inline comment image loads, `ImageBlockView` swaps its aspect constraint and pins a brand-new `UIImageView` (never laid out) into its box, then fires `onContentSizeChange` → the cell's `onBodyImageLoaded` → `PostDetailViewController.swift:1950-1953`: `tableView?.performBatchUpdates(nil)` — the ANIMATED re-measure. Inside that implicit animation transaction the image view's frame interpolates from `.zero` to its fill-frame (with `scaleAspectFill` cropping shifting mid-flight) — the visible zoom. The post header cell had the identical symptom and fixed it in `PostDetailHeaderCell.adjustHeightForChange` (:1054-1067) with `UIView.performWithoutAnimation { beginUpdates(); endUpdates() }` plus a comment describing the zoom; `DMThreadViewController.swift:213-217` copied the comment cell's ANIMATED pattern ("mirrors the comment cell's re-layout") and inherits the glitch. All other MarkdownBodyView hosts re-measure without animation (Person/Community reassign `tableHeaderView`; Instance About wires no re-measure at all — a separate latent gap, deliberately NOT this plan's scope). Introduced by ec6e1a50 (comment path) and 563b834d (DM copy). No existing test exercises the animated re-measure.

**Architecture (binding):** one new `UITableView` extension helper — `Spud/Utils/Extensions/UITableView+NonAnimatedRemeasure.swift`:

```swift
extension UITableView {
    /// Re-measures self-sizing rows in place WITHOUT the implicit
    /// batch-updates animation. Use this whenever async content (an inline
    /// body image, a late thumbnail) changes a row's height after display:
    /// the newly installed subviews have never been laid out, so an animated
    /// re-measure interpolates their frames from .zero — reading as the
    /// content zooming in from a corner (the post-header cell documented
    /// this exact symptom; see PostDetailHeaderCell.adjustHeightForChange).
    func remeasureRowHeightsWithoutAnimation() {
        UIView.performWithoutAnimation {
            performBatchUpdates(nil)
        }
    }
}
```

All THREE hosts route through it (the header's `begin/endUpdates` pair is behavior-equivalent to `performBatchUpdates(nil)` — consolidating is the DRY move, and the helper doc carries the invariant):
- `PostDetailViewController.swift:1950-1953` — `cell.onBodyImageLoaded = { [weak tableView] in tableView?.remeasureRowHeightsWithoutAnimation() }` (keep the existing comment's intent, one line).
- `DMThreadViewController.swift:213-217` — same substitution.
- `PostDetailHeaderCell.adjustHeightForChange` (:1054-1067) — body becomes `tableView?.remeasureRowHeightsWithoutAnimation()`; KEEP (condense, don't delete) the explanatory comment about the mid-push zoom symptom, now pointing at the helper.

**Tech Stack:** UIKit, Swift Testing (SpudTests).

## Global Constraints

- Zero behavior change beyond removing the animation: same re-measure, same callbacks, same heights. `ImageBlockView`, `MarkdownBodyView`, and all height-propagation callbacks are UNTOUCHED.
- Verify per task: `make build` + `make test-only ONLY=SpudTests`. Snapshot suite: `make snapshot` must stay 261/261 (no refs change — nothing rendered differently at rest). Environment is GREEN (Dynamic Type resolved 2026-07-06; sim content_size must read `large`).
- `mint run swiftformat <changed files>` before each commit; explicit-path staging (442 cosmetic-M annex refs in the worktree — never `git add -A`). Conventional commits; push is user-gated. No emojis.
- New file requires `make project` before building.
- Worktree: `/Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/comment-image-zoom`, branch `worktree-comment-image-zoom` off main 3899286d.

---

### Task 1: Non-animated re-measure helper + both fixes + regression test

**Files:**
- Create: `Spud/Utils/Extensions/UITableView+NonAnimatedRemeasure.swift` (helper above, verbatim doc intent).
- Modify: `Spud/Scenes/PostDetail/Content/PostDetailViewController.swift` (:1950-1953), `Spud/Scenes/Inbox/DMThreadViewController.swift` (:213-217), `Spud/Scenes/PostDetail/Content/Header/PostDetailHeaderCell.swift` (:1054-1067) — route all three through the helper.
- Test: `SpudTests/NonAnimatedRemeasureTests.swift` (new).

**Test design (TDD; the RED must demonstrate the animation):** build a real `UITableView` harness in a laid-out window with a self-sizing cell whose content view height is driven by a mutable constraint; display it; then grow the constraint and trigger the re-measure the way the production code does. RED (pre-fix shape, calling bare `performBatchUpdates(nil)`) asserts that some layer in the resized cell's subtree carries animations (`layer.animationKeys()` non-empty, checked synchronously inside/immediately after the update — UITableView attaches the height animations during the call). GREEN (via the helper) asserts NO layer in the cell subtree has animation keys after the same sequence, and the row's final height equals the grown height (the re-measure still happened). If the animation-keys probe proves flaky/untestable in the harness (UIKit version sensitivity), STOP and report before substituting a weaker assertion — the fallback (assert the three call sites compile against the helper + manual sim verify) is a materially weaker lock the controller must sign off.

**STOP:** if converting the header's `begin/endUpdates` to `performBatchUpdates(nil)` produces ANY observable difference in the existing header tests/snapshots, drop the header consolidation (leave it on `performWithoutAnimation { begin/endUpdates }` with a pointer comment) and report — the two broken sites are the mandatory scope.

- [ ] Steps: RED harness test (animated shape) → helper + three call-site swaps → GREEN → `make build` + `make test-only ONLY=SpudTests` → swiftformat → commit `fix: never animate row re-measure when inline body images load` (explicit paths).

### Task 2: Docs + gates + review + merge

- [ ] Docs: find the capability doc covering inline body images (grep docs/features for "inline image"; likely the post-detail/comments-related capability page(s)) and add the behavior rule: an image finishing its load snaps the row to its new height without animation (no zoom); note the same rule for DM bubbles' doc if one exists. Update the README capability table/by-area map only if wording became inaccurate. Commit `docs: inline body images snap row height without animation`.
- [ ] Gates: full `make snapshot` 261/261 (no refs changed); `mint run swiftformat --lint .` clean.
- [ ] Whole-branch review (fresh reviewer, most capable model): risk list = the header consolidation's behavior-equivalence (begin/endUpdates → performBatchUpdates(nil) inside performWithoutAnimation), the regression test not being vacuous (would it fail on the pre-fix code?), no other `performBatchUpdates(nil)` image-load sites missed (grep), docs accuracy.
- [ ] ONE fix agent for findings; re-run gates.
- [ ] Merge protocol (workspace CLAUDE.md): re-check `main..worktree-comment-image-zoom` + shared-checkout dirt overlap RIGHT BEFORE merging (the shared checkout currently carries another agent's uncommitted edits to root `CLAUDE.md` + `SpudSnapshotTests/CLAUDE.md` — this branch must not touch either); `git annex restage` in the shared checkout first; `git merge --no-ff`. Push only on the user's explicit word.
