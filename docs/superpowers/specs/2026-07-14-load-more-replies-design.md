# Load More Replies — Design Spec

**Date:** 2026-07-14
**Status:** Approved (brainstorm) — pending implementation plan

**Goal:** Make the "N more replies" placeholder row on post detail work. Tapping it fetches the missing comment subtree and splices it into the tree in place (inline expansion, scroll position preserved), on both v3 and v4 servers. Today the row is modeled and rendered but was never wired end-to-end — tapping does nothing.

---

## 1. Problem (root cause)

The "N more replies" row is an **unimplemented feature**, not a broken wire. It is modeled and rendered but nothing responds to a tap and no service can fetch a subtree for display:

- **Modeled:** `CommentImporter.upsertComments` inserts a placeholder `CommentElementRecord` (`commentId == nil`, `moreChildCount`, `moreParentId`) after any loaded leaf whose server-reported `childCount > 0` (`LemmyCommentImportHelper.findCommentsWithMissingChildren`). The placeholder carries the parent's server id and descendant count.
- **Rendered:** `PostDetailCommentViewModel` sets `isMore`/`moreText` ("1 more reply" / "N more replies"), and `PostDetailCommentCell` shows it with `accessibilityTraits = .button` and a "Loads more replies" VoiceOver hint.
- **Not wired (four independent gaps):**
  1. `PostDetailCommentCell` explicitly disables its only content tap recognizer for these rows (`collapseTapGestureRecognizer.isEnabled = !viewModel.isMore`).
  2. The "more" text is styled like a link but carries **no `.link` URL attribute**, so `LinkLabel` registers nothing tappable.
  3. `PostDetailViewController` has **no `tableView(_:didSelectRowAt:)`**.
  4. There is **no load-more closure** on the cell and **no `LemmyService` method that fetches a comment subtree for display** — `fetchComments` fetches only the whole-post listing; `fetchSubtreeChildCount` fetches a subtree solely to return an `Int` count (reminder polling), never persisting/displaying it.

The `.button` trait + "Loads more replies" hint confirm this was intended to be tappable and simply never finished.

**Two facts that shaped the design (verified):**
- `CommentRecord` does **not** persist the comment `path` (only `depth`/`position` live on `CommentElementRecord`), so the tree cannot be rebuilt from the DB alone — the merge must splice using the fetched comments' own paths.
- `findCommentsWithMissingChildren` is **sound** (not over-producing): it flags a comment only when it is a *leaf of the fetched set* with `childCount > 0`, which genuinely means unloaded descendants. No detector change is needed.

---

## 2. Approved decisions

1. **Interaction:** expand inline in place (not a focused/permalink "continue thread" screen).
2. **Extent:** one tap loads the **whole subtree** (paginate internally, bounded cap); a subtree beyond the cap leaves a fresh deeper "more replies" row that self-heals on another tap.
3. **Merge:** **Approach A — localized splice**, additive, no schema migration, leaving the working whole-tree import path untouched.

---

## 3. LemmyKit change (paired, repo `LemmyKit/`)

The version-neutral surface Spud consumes (`getCommentsNeutral(postId:sort:pageCursor:)`) exposes only `postId`/`sort`/`pageCursor` — no `parentId`. The raw Lemmy v3 **and** v4 GetComments requests both support `parent_id`, and a legacy v3-only `getComments(parentID:maxDepth:)` wrapper already exists, but the neutral surface does not. Adding cross-version subtree fetch therefore requires a paired LemmyKit change.

- **New neutral method** `getCommentsNeutral(parentId:sort:pageCursor:)` in `Sources/LemmyKit/LemmyApi+GetCommentsNeutral.swift`, returning `Page<CommentView>` — same shape as the existing whole-post method, with `parentId` added and `postId` dropped.
  - **v3 path:** send `parent_id` (no `max_depth` → whole subtree), return the tree as a single page (as the existing v3 path does; v3 has no cursor).
  - **v4 path:** send `parent_id` + `page_cursor` + `sort` + `type_: .all`, cursor-paginated (as the existing v4 path does).
  - No `maxDepth` parameter — symmetric with the existing whole-post neutral method, which deliberately sends no `max_depth`. "Whole subtree" = no depth bound; the server's page `limit` is the only bound, and the frontier-placeholder regeneration (§5.4) covers anything the page bound cut off.
- **Tests:** neutral request-shape + decode tests for both v3 and v4, mirroring the existing `getCommentsNeutral` tests.
- Commit on `LemmyKit` `main`. **No release tag** — the Spud pin is a `revision:` (consistent with the current unvalidated-v4 posture; see the "don't tag unvalidated releases" note in the workspace CLAUDE.md).

---

## 4. Spud service (`LemmyService`, `SpudDataKit`)

- **New** `fetchMoreComments(serverPostId:parentServerId:sortType:)`:
  - Loops `getCommentsNeutral(parentId:sort:pageCursor:)` following `Page.nextPage`, bounded by a page cap (reuse the pattern/constant behind `maxSubtreeChildCountPages`), accumulating the whole subtree's `CommentView`s.
  - Calls the new importer splice (§5) with the accumulated views.
  - On network/decoding failure throws `LemmyServiceError(from:)` (the VM surfaces it). Unlike `fetchSubtreeChildCount` (best-effort, returns nil), this **throws** because the UI must distinguish success from failure to drive the loading/error state.

---

## 5. Spud importer (`CommentImporter`, Approach A — localized splice)

**New** `spliceMoreComments(forServerPostId:accountId:siteId:sortType:parentServerId:comments:)` — one write transaction:

1. **Locate the placeholder** `CommentElementRecord` for `(postRowId, sortType)` with `commentId == nil` and `moreParentId == parentServerId`. If absent (already loaded / stale), **no-op** (idempotent — a double-tap or a re-splice after the observation already updated must not corrupt positions).
2. **Upsert** every fetched comment record via the existing private `upsertComment(from:…)` (this also refreshes the parent's `childCount`). Lemmy's `parent_id` fetch returns the parent comment itself alongside its descendants; the splice must not assume it does, however (see step 3).
3. **Thread** the fetched set with the existing `LemmyCommentImportHelper.sort(comments:)` and emit element rows for every fetched comment **except the one whose server id equals `parentServerId`** (it already has an element) — so the splice is correct whether or not the response echoes the parent — using each comment's absolute `CommentPath(path:).depth`, identical to the whole-tree import (no relative-depth math).
4. **Splice positions:** let `P` = placeholder position and `K` = number of new element rows. `UPDATE commentElement SET position = position + (K - 1) WHERE postId = ? AND sortType = ? AND position > P`; delete the placeholder; insert the K new rows at positions `P … P + K - 1`. (Net position delta is `K - 1` because the single placeholder row is removed.)
5. **Regenerate frontier placeholders:** run the existing `findCommentsWithMissingChildren` over the fetched set; for any leaf still reporting `childCount > 0`, insert a fresh placeholder (same shape as `upsertComments`) at the correct spliced position/depth.

The existing GRDB observation (`PostDetailObservations`) emits the new rows and the tree re-renders — no VC-level tree mutation.

---

## 6. UI wiring (`Spud` — `PostDetailCommentCell` / `…ViewModel` / `PostDetailViewController`)

- **Tap target:** add a dedicated `moreTapGestureRecognizer`, **enabled only when `viewModel.isMore`** (the collapse recognizer stays disabled for these rows), calling a new `moreTapped?()` closure on the cell. Wire it in the cell-provider next to the existing closures (`linkTapped`, `collapseTapped`, …). This matches the cell's existing closure pattern rather than introducing a `didSelectRowAt`.
- **Loading state:** the view model holds an in-flight `Set<parentServerId>`; the more-row's `PostDetailCommentViewModel` exposes `isLoadingMore`. On tap → insert into the set, refresh the row via `UITableView.remeasureRowHeightsWithoutAnimation()` (spinner shown, re-tap ignored), and run `fetchMoreComments` in a `Task`. On success the observation replaces the placeholder row; on completion (success or failure) remove from the set.
- **Accessibility:** keep the `.button` trait + "Loads more replies" hint for the idle row; while loading, swap the label/hint to "Loading replies" and drop `.button` so VoiceOver doesn't invite a re-tap.

---

## 7. Error handling

On fetch failure: remove the parent from the in-flight set, revert the row to its idle "N more replies" (tappable) state, and surface the error via the existing `AlertService` toast ("Couldn't load replies"). The row itself is the retry affordance (tap again). No silent swallow — the failure is both toasted and (per existing diagnostics conventions) loggable.

---

## 8. Testing

- **LemmyKit:** neutral `getCommentsNeutral(parentId:…)` request-shape + decode tests, v3 and v4.
- **SpudDataKit:** `spliceMoreComments` importer tests — seed a truncated tree with a placeholder; splice a fetched subtree; assert element count/positions/depths, placeholder removed, deeper-frontier placeholder regenerated; and that a re-splice with the placeholder already gone is a no-op (idempotent).
- **Spud:** view-model test — tapping sets `isLoadingMore` and calls the service; the failure path clears the flag and surfaces the error.
- **Snapshot (iPhone 17 Pro / portrait):** the more-row loading (spinner) state, if it renders deterministically.
- **UITest (optional):** SBT-stubbed neutral subtree request → tap the more-row → asserted new comments appear (XCUITest; idb tap automation is dead here).

---

## 9. Documentation & rollout

- **Feature docs:** update the post-detail/comments capability doc under `docs/features/` (behavior + Given/When/Then scenarios) **and** the README capability table **and** the "Feature coverage by area" map.
- **Dev workflow (paired repos):** iterate with the LemmyKit **local-path override** (`path:` in `project.yml`, left **uncommitted** — stage only code, never `project.yml`); after applying it, force a clean resolve so the local path wins over the stale remote pin. **Bump the committed `revision:` pin LAST**, once all Spud work is done and green.
- **Branch/merge:** work is isolated in the `feat/load-more-replies` worktree off local `main`; re-check `main..HEAD` and file overlap right before merging (shared checkout, parallel agents).

---

## 10. Out of scope / known limitations

- A subtree beyond the page cap leaves a deeper frontier "more replies" row (progressive, self-healing) rather than loading everything in one tap — accepted.
- No change to the whole-tree import, the `findCommentsWithMissingChildren` detector, or the DB schema (no migration).
- No focused/permalink "continue thread" screen (the interaction we ruled out).
- Very large subtrees whose *direct* children exceed one page may leave some mid-level siblings unreachable until a later pagination pass — the bounded internal pagination (§4) mitigates this for all but pathological cases.
