# Comment Fetching Completeness — Design Spec

**Date:** 2026-07-22
**Status:** Approved (brainstorm) — pending implementation plan

**Goal:** The comment tree Spud shows is the tree the server has — on Lemmy v3, Lemmy v4, and PieFed alike — and where it genuinely cannot be, the UI says so instead of implying completeness. Re-importing a tree must be safe to do while someone is reading it.

---

## 1. Problem

A bug report ("this post shows 117 comments in the header and none in the body", slrpnk.net post 40534551) exposed one defect that has since been fixed, and four more that have not.

### Already fixed (commits `002166db` / LemmyKit `02d78ac`), for context

The v3 post-scoped fetch sent no `max_depth`, so the server returned a flat 10-item slice instead of a tree, and `LemmyCommentImportHelper.sort` silently dropped every comment whose parent was absent. Both are fixed. This spec covers what that investigation surfaced underneath.

### Still broken

1. **v4 and PieFed only ever show page one.** `LemmyService.fetchComments` issues a single `getCommentsNeutral` call and discards `page.nextPage`. On v3 that is harmless — v3 returns the whole tree in one response and its `nextPage` is always nil. But v4 and PieFed comment listings genuinely paginate, so on Lemmy 1.0 and on PieFed the tree is truncated at page one, permanently and dialect-wide. `LemmyService.swift:1243-1246` already documents this in a comment about a different method.

2. **"Load more replies" sends no `limit`.** The parent-scoped v3 fetch omits `limit`, so Lemmy's default of 10 applies. Measured against slrpnk.net comment 23426578, whose subtree has 28 children: 10 returned without `limit`, 29 with `limit=50`. Each tap therefore loads a fraction of the subtree and re-surfaces a frontier row.

3. **The initial v3 depth is shallower than it needs to be.** `postCommentTreeMaxDepth` is 8.

4. **Every re-import destroys reader state.** `CommentImporter.upsertComments` deletes all `CommentElementRecord` rows for `(post, sortType)` and reinserts them. `CommentElementRecord.id` is an auto-increment rowid and the diffable snapshot keys on it (`Item.comment(elementId: Int64)`), so every re-import mints new identities for unchanged comments. `PostDetailViewModel.swift:523` then runs `collapsedElementIds.formIntersection(existingIds)`, which empties. **Every pull-to-refresh silently discards all collapse state and all in-flight "load more" state, and churns every row identity.** This is why the current design fetches once and never revisits, and it blocks any incremental loading.

---

## 2. Measured facts that shaped the design

All verified live against slrpnk.net (Lemmy 0.19.20) and lemmy.world during the investigation.

- **`max_depth` is a result-shape switch, not a filter.** With it, the server returns an ancestor-complete tree. Without it, a flat slice ordered by `sort` and bounded by `limit`.
- **With `max_depth` set, the server ignores both `limit` and `page`, and caps the response at 300 comments.** On a 537-comment post: `max_depth=8`, `&limit=50`, `&limit=20`, `&page=2` all return exactly 300.
- **The 300-cap cut is ancestor-complete and fully reachable.** That same post has exactly 21 top-level comments (`max_depth=1` returns 21) and all 21 are present at the cap; orphan count is 0 at every depth tried (1, 2, 3, 5, 8, 20); and 30 of the returned comments claim children that were not loaded, so 30 "load more replies" frontier rows express the truncation. **No new affordance is needed for the v3 cap.**
- **Depth is nearly free.** 537-comment post: `max_depth=8` → 1,596,078 bytes; `max_depth=20` → 1,608,548 bytes (+0.8%), both capped at 300. On the 135-comment post, `max_depth=8` returns 132 and `max_depth=12` or deeper returns the complete tree.
- **`limit` has a hard ceiling.** `limit=300` fails with `{"error":"couldnt_get_comments"}`; `limit=50` succeeds. The constant must be capped, not merely "large".
- **Server comment counts do not equal tree size.** The 135-comment post returns 138 rows at depth 12. Count-vs-rows arithmetic is not a usable signal for "is the tree complete".

---

## 3. Approved decisions

1. **Scope:** data layer plus honest UI states. No new screens or interaction models. Progressive rendering, payload size, and scroll performance on huge threads are out of scope.
2. **Initial load on paginated dialects:** paint page 1 immediately, then finish the remaining pages in the background and re-import the complete set. Fast first paint *and* completeness, with no taps.
3. **Stable row identity is a prerequisite**, built first — decision 2 is unsafe without it, and it fixes pull-to-refresh independently.
4. **Partial state is derived from the fetch, never from counters.** Whether pagination exhausted the listing is known exactly at the source. Comparing the server's comment count to loaded rows is unreliable (fact 6 above) and is the reconciliation approach this project already considered and rejected.

---

## 4. Components

Build order is 0 → 4. Each is independently testable.

### Component 0 — Stable comment row identity (`CommentImporter`)

`upsertComments` becomes a reconciling upsert instead of a destructive rebuild:

- Load the existing `CommentElementRecord` rows for `(postId, sortType)` and key them by `commentId` (real comments) and by `moreParentId` (placeholders, already a semantic key).
- For a comment still in the tree: update `position` and `depth` in place, preserving `id`.
- Insert rows for comments new to the tree; delete only rows whose comment (or placeholder parent) left it.

Element ids then survive a re-import, so collapse state, in-flight "load more" state, and scroll position survive, and GRDB observations emit real diffs rather than a wholesale replacement.

Chosen over re-keying the diffable `Item` and collapse set on comment server id: this is contained entirely in `CommentImporter`, leaves the PostDetail view-model and view-controller untouched, and fixes pull-to-refresh at the same time.

`spliceMoreComments` already inserts in place and is unaffected, but its placeholder regeneration must stay consistent with the new reconciliation.

### Component 1 — Wire requests (`LemmyKit`)

- Raise `postCommentTreeMaxDepth` from 8 to **15**. The 300-cap bounds server work regardless of depth, so a deeper request is nearly free (+0.8% payload) and returns complete trees for ordinary posts, reducing "load more replies" taps for the same server cost. 15 rather than something larger: depth 12 already completed the 135-comment test post, 15 leaves headroom, and it stays modest in case an instance does not enforce the 300-comment cap. The constant's doc comment must record that rationale.
- Add an explicit `limit` to the **parent-scoped** v3 fetch (`getCommentsNeutralV3(parentId:sort:)`), capped at Lemmy's ceiling of 50. Do **not** add `limit` to the post-scoped fetch — `max_depth` makes the server ignore it.
- v4 and PieFed wire shapes are already correct.

### Component 2 — Paginating fetch (`LemmyService.fetchComments`)

`fetchComments` becomes: fetch page 1 → import it → while a `nextPage` cursor remains and a page bound is not exceeded, fetch the next page, accumulate, and re-import the accumulated set.

- On v3 `nextPage` is always nil, so the loop runs once and behavior is unchanged.
- The bound is a named constant set to **10 pages**, mirroring the existing `maxSubtreeChildCountPages`; hitting it is reported, not swallowed.
- Re-import is safe because of component 0.
- The background continuation must be cancellable and must not race the existing cancel-and-replace logic in `PostDetailViewModel.fetchComments` (sort change, retry).

### Component 3 — Honest partial states

- **Bound reached:** when pagination stops with a `nextPage` still outstanding, the tree gets a terminal "Load more comments" row, modeled on the existing "N more replies" row (tappable, spinner while loading, reverts with a toast on failure). On v3 this never appears.
- **Mid-pagination failure:** today a failure on page 3 of 5 throws away pages 1–2 and drops to the error state. Instead, keep what arrived, leave it on screen, and surface the failure the way a refresh failure already is — a toast plus retry — matching the existing rule that `CommentsBackground.failed` only applies when there are no comments to show.
- The existing `CommentsBackground` skeleton / empty / failed states are already honest for "nothing loaded" and are unchanged.

### Component 4 — Tests

- **LemmyKit:** request-shape tests (stub transport, captured path) asserting the post-scoped request carries `type_=All` and the depth constant and *no* `limit`, and the parent-scoped request carries `type_=All` and `limit` at the ceiling.
- **SpudDataKit — component 0:** a comment present in both imports keeps its element `id`; a departed comment's row is deleted; a new comment gets a row; placeholders reconcile by `moreParentId`; ordering after reconciliation matches a fresh import.
- **SpudDataKit — component 2:** multi-page accumulation over stubbed v4 and PieFed transports; single-page v3 unchanged; stop at the page bound reports the outstanding cursor; a mid-pagination failure keeps earlier pages.
- **Spud:** the terminal "load more comments" row appears only when a cursor is outstanding, and the mid-failure path keeps rows on screen rather than switching to `CommentsBackground.failed`.
- **Regression guard:** the orphan-tolerance and child-before-parent tests added with the original fix stay green.

---

## 5. Cross-repo mechanics

Component 1 lands in `LemmyKit` and reaches Spud only via a pushed commit plus a `revision:` bump in `Spud/project.yml`. Per the workspace CLAUDE.md the pin bump is the final step, and the pin stays a `revision:` — not a release tag — while the PieFed dialect awaits human validation.

---

## 6. Non-goals

- Progressive or incremental *rendering* of a large tree; payload size; scroll performance on huge threads.
- Changing where the header's comment count comes from (`PostView.counts` stays authoritative).
- Any new affordance for the v3 300-comment cap — the existing frontier rows already cover it (fact 4).
- Reopening the rejected count-vs-tree reconciliation.
