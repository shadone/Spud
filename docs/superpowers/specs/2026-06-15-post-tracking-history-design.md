# Post tracking, history & new-comment delta

Date: 2026-06-15
Status: Design approved, ready for implementation plan

## Problem

Three related gaps in how Spud helps you return to and re-read posts:

1. **Coming back to a post is hard.** You see an interesting post, want to read more
   comments later, and then can't find it again. There is no "recently read" list and
   no way to search the posts you've already encountered.
2. **There is no record of what you've seen.** Spud knows which posts you *opened*
   (`PostRecord.isRead`, server-synced) but not which posts merely *appeared on screen*
   as you scrolled. The widest "I can't find that post" net needs the latter.
3. **Returning to a post doesn't show what changed.** You read a thread, maybe comment,
   then stumble back on it hours later — and there is no indication of which comments
   are new since you last looked.

The eventual north star is push notifications for new activity on posts you care about,
but that is explicitly a later phase; the data model here must not preclude it.

## Decisions (confirmed)

- **Follow = enhanced Save.** Reuse Lemmy's existing native Save (already wrapped:
  `savePost`, `isSaved`, `.saved` feed) as the single "come back later" anchor. We do
  **not** add a separate local "follow" concept. New-comment tracking and (future) push
  layer onto saved posts.
- **Seen tier is in scope**, and its purpose is to **widen recall/search** — record posts
  that appeared on screen so "find that post I saw" works even when you never opened it.
  Local-only; never synced to the server.
- **"New since last visit" = last time I opened it.** One `lastOpenedAt` timestamp per
  post. A comment is new iff `comment.published > previousLastOpenedAt`.
- **Architecture: shared interaction-log foundation, phased surfaces.** One local
  `postInteraction` table is the foundation; surfaces ship in value order (delta →
  history+search → seen-capture → push).
- **History lives in the account/profile area** (alongside Saved), as a personal-data
  surface.
- **Retention defaults:** seen-only entries pruned after 30 days; opened entries kept
  1 year; saved posts kept indefinitely.
- **New-comment visuals are deferred to the Claude Design pipeline.** This spec pins the
  *behavior* (which comments flag, the count, jump-to-new); exact marker styling is out
  of scope here.

## Current state (from codebase)

- **Persistence:** GRDB / SQLite in `SpudDataKit/Services/AppDatabase/`, in the App Group
  container (`group.info.ddenis.Spud.shared/AppDatabase/AppDatabase.sqlite`) shared with
  the widget and extensions. Migrations are `DatabaseMigrator` cases in
  `AppDatabase+Migrations.swift` (add the next case; never edit existing ones). Records
  are pure structs in `Records/` (one file per type). Importers translate Lemmy responses;
  `*Observations.swift` expose `AsyncStream`s; `*Queries.swift` expose one-shot reads.
- **Post record** (`Records/Post.swift`, table `post`): has `id: Int64` (local row id),
  `postId: Int64` (server id), `accountId: Int64`, `isRead: Bool`, `isSaved: Bool`,
  `isHidden: Bool`, `published: Date`, `createdAt`, `updatedAt`. **No `lastOpenedAt`.**
- **Comment record** (`Records/Comment.swift`, table `comment`): has `localCommentId`,
  `postId`, `isSaved`, `published: Date` (suitable for "new since"), `createdAt`,
  `updatedAt`. Tree order/depth in `CommentElementRecord` (table `commentElement`).
- **Read (opened) tracking — already implemented & server-synced.** `LemmyService.markAsRead`
  → `LemmyApi.markPostAsRead` → `AppDatabase.setPostIsRead`; `PostImporter` mirrors
  `PostView.read`. `PostDetailViewController.markAsRead()` fires on appearance. A
  "Hide read posts" filter (`HideReadPostsFilter.swift`) already consumes `isRead`.
- **Save — already implemented & server-synced.** `LemmyService.setSaved` → `LemmyApi.savePost`
  / `saveComment`; importers mirror `view.saved`; `FeedType.saved(sortType:)` is a
  server-side feed.
- **Post detail:** `PostDetailViewController` / `PostDetailViewModel` /
  `PostDetailObservations.swift`. Comments fetched via `LemmyService.fetchComments`
  (`LemmyKit.getComments(postID:sort:maxDepth:8)`), mirrored to `comment` /
  `commentElement`, observed via `observePostDetailCommentTree()` →
  `AsyncStream<[PostDetailCommentRow]>`. Re-fetched on sort change.
- **No history / recently-viewed surface anywhere. No per-comment read state.**
- **UI is UIKit** (scenes, coordinators, view models). View models are `@Observable`,
  bound via `ObservationStream.values(of:)`. Feeds render in a UIKit list (cell
  display callbacks are the natural impression hook). Swift 6, strict concurrency complete,
  iOS 18.

## Architecture

### Foundation: `postInteraction` table (local-only)

New GRDB record `PostInteractionRecord` in `Records/PostInteraction.swift`, table
`postInteraction`, added via the next migration case. Local-only — **never** sent to
Lemmy, never mirrored from an importer.

Keyed by `(accountId, postServerId)` with a denormalized snapshot so a history entry
renders and is searchable **even after `PostRecord` is evicted/refreshed** (this is what
makes the Seen→search payoff cheap and durable, and decouples history from the post cache):

| Column | Purpose |
|---|---|
| `id: Int64` | local PK |
| `accountId: Int64` | owning account (matches `PostRecord.accountId`) |
| `postServerId: Int64` | Lemmy post id (durable across cache eviction) |
| `titleSnapshot: String` | render + search without a `PostRecord` join |
| `communityName: String` | render + scope |
| `instanceHost: String` | render + disambiguate federated duplicates |
| `thumbnailUrl: String?` | render |
| `author: String?` | render |
| `firstSeenAt: Date?` | first on-screen impression |
| `lastSeenAt: Date?` | most recent impression (Seen ordering) |
| `seenCount: Int` | impression count |
| `lastOpenedAt: Date?` | most recent detail open (Recently-Read ordering + delta ref) |
| `openedCount: Int` | open count |
| `lastKnownCommentCount: Int?` | new-activity hook for future push |

Indexes: unique `(accountId, postServerId)`; ordering indexes on `lastOpenedAt` and
`lastSeenAt`; FTS index over `titleSnapshot` (+ `communityName`) for search.

A small recorder (e.g. `PostInteractionRecorder`, or methods on `AppDatabase`) exposes:
- `recordOpened(accountId:postServerId:commentCount:snapshot:)` — upsert, set
  `lastOpenedAt = now`, bump `openedCount`, update `lastKnownCommentCount`. **Returns the
  previous `lastOpenedAt`** so the delta feature can read it before it is overwritten.
- `recordSeen(accountId:postServerId:snapshot:)` — upsert, set `lastSeenAt = now`, bump
  `seenCount` (set `firstSeenAt` if nil).
- `prune()` — apply the retention policy.

Reads via `PostInteractionObservations.swift` (AsyncStream history lists) and
`PostInteractionQueries.swift` (sync `previousLastOpenedAt` lookup for the delta).

### Phase 1 — New-comment delta (post detail)

Smallest piece, highest daily value, builds directly on the foundation + existing
`comment.published`.

- On opening post detail (where `markAsRead()` already fires), call `recordOpened(...)`
  and capture the **returned previous `lastOpenedAt`** as `previousVisitAt`.
- In `PostDetailObservations.observePostDetailCommentTree()`, derive
  `isNew = comment.published > previousVisitAt` per `PostDetailCommentRow`.
- Surface (behavior only; visuals deferred): an unread marker on new comment rows, a
  header count ("N new comments since your last visit"), and a "jump to first new"
  affordance.
- Edge cases baked in:
  - **First-ever visit** (`previousVisitAt == nil`) → nothing is flagged new.
  - **Your own just-posted comment** never counts as new.
  - Compare on `published`, **not** `updated`, so edits don't re-flag old comments.

### Phase 2 — Recently-read / seen History + search

A History surface in the **account/profile area**, alongside Saved.

- List ordered by `lastOpenedAt` (Recently Read) with a segment for **Seen**
  (`lastSeenAt`).
- Search field over `titleSnapshot` (+ `communityName`) via the FTS index, with a scope
  toggle: **All seen / Only opened / Saved**. (Covers both "list of posts I read recently"
  and "search through only read posts".)
- Tapping an entry opens the post, re-fetching from the server if it has been evicted from
  the `PostRecord` cache.

### Phase 3 — Seen-impression capture (feeds)

Most finicky and perf-sensitive — ships last.

- Hook the feed list's cell-display lifecycle: a post cell that stays on screen past a
  short dwell (≈500ms, to skip fast-scroll noise) triggers `recordSeen(...)` with the
  cell's snapshot.
- Debounce/batch writes (coalesce a scroll burst into one transaction) to protect feed
  scroll performance.
- Isolated to the feed list layer; no change to the foundation API.

### Phase 4 — Push notifications (future; design hooks only, NOT built here)

Out of scope to build now; the foundation must merely not preclude it.

- Lemmy has no native push, so this requires polling (e.g. a `BGAppRefreshTask` comparing
  the server's current comment count against `lastKnownCommentCount` for saved posts) plus
  APNs delivery.
- Because Follow = Save, **per-post mute** is recommended so saving an article to read
  later does not turn into comment-spam. (Adds a `pushMuted: Bool` to the interaction
  record when this phase is built — noted, not added now.)

### Privacy & retention

- The interaction log is **local-only**: never sent to Lemmy, never part of any export
  unless explicitly requested. (Consistent with the project's privacy posture.)
- `prune()` retention: seen-only entries (no `lastOpenedAt`) older than **30 days** are
  deleted; opened entries are kept **1 year**; saved posts (`PostRecord.isSaved`) are
  exempt and kept indefinitely. Run on app launch (and optionally periodically).

## Task list (by phase)

**Phase 0 — Foundation**
1. `PostInteractionRecord` + `postInteraction` migration (table, indexes, FTS).
2. `PostInteractionRecorder` with `recordOpened` (returns previous `lastOpenedAt`),
   `recordSeen`, `prune`.
3. `PostInteractionObservations` + `PostInteractionQueries`.
4. Wire `prune()` into app launch.
5. Unit tests: upsert semantics, previous-timestamp return, retention pruning.

**Phase 1 — New-comment delta**
6. Call `recordOpened` from the post-detail open path; thread `previousVisitAt` into the
   view model.
7. Add `isNew` to `PostDetailCommentRow` in `PostDetailObservations`.
8. New-comment count + "jump to first new" in `PostDetailViewModel` / `…ViewController`
   (behavior; visuals via Claude Design).
9. Tests: first-visit (nothing new), own-comment excluded, edit-doesn't-reflag,
   correct count.

**Phase 2 — History + search**
10. History scene (view controller + `@Observable` view model) in the account/profile area.
11. Recently-Read / Seen segment, backed by `PostInteractionObservations`.
12. FTS search + scope toggle (All seen / Only opened / Saved).
13. Open-from-history (re-fetch if evicted).
14. Tests / snapshot tests for the history list states.

**Phase 3 — Seen capture**
15. Feed cell dwell detection + debounced `recordSeen`.
16. Perf check on scroll; batch-write verification.
17. Tests for dwell threshold + coalescing.

**Phase 4 — Push (future, not now)**
- Design hook only: keep `lastKnownCommentCount` populated; add `pushMuted` when built.

## Out of scope / deferred

- Push notification delivery, background polling, APNs (Phase 4 — separate initiative).
- Per-comment read state (only post-level "new since last open" is in scope).
- "New since 2 visits ago" multi-checkpoint history (single `lastOpenedAt` only).
- Exact new-comment marker styling (Claude Design pipeline).
- User-configurable retention windows (hardcoded defaults for now).
