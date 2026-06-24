# Durable, optimistic composing (comments + posts)

- **Date:** 2026-06-24
- **Status:** design — pending implementation
- **Surfaces:** `iphone`, `ipad`
- **Targets touched:** `Spud`, `SpudDataKit`
- **Replaces/updates docs:** `docs/features/draft-persistence.md`, `docs/features/replying.md`, `docs/features/new-post.md`

## Summary

Today, composing a comment or a post is a blocking, throwaway interaction: you
tap Post, a spinner spins through the network round-trip, and only then does the
content appear; if you dismiss the sheet, your text is gone; if the network is
bad, you get an error alert and must retry by hand. This redesign makes composed
content **instant, durable, and self-healing**:

1. **Instant** — the moment you tap Post, your content shows up. A comment slots
   into the comment tree in its real position with a `Sending…` state; a new post
   takes you straight to its (pending) post-detail screen.
2. **Durable** — drafts and in-flight sends are persisted to the database. They
   survive sheet dismissal, app backgrounding, and app termination. Nothing you
   type is ever silently lost.
3. **Self-healing** — sends run in a background queue that retries on its own
   (exponential backoff, auto-resume when the network returns), and failures are
   parked for manual retry/edit/discard rather than discarded.

These three properties apply to both **comments** (post-detail replies) and
**new posts**, unified behind one storage layer and one send engine.

## Goals

- Posting a comment shows it immediately, inline in the tree, before the server
  confirms.
- Posting a new post immediately navigates to a pending post-detail view.
- A composed comment/post is never lost: drafts auto-save and persist across app
  launches; a failed send is parked (kept), never discarded.
- Sends retry automatically on bad/intermittent networks and resume when
  connectivity returns, including across app restarts.
- One recovery home ("Drafts & Outbox") lists every draft, in-flight, and failed
  item so nothing is unreachable.
- Per-target silent draft restore: reopening the same composer prefills your
  unsent text.

## Non-goals (this iteration)

- **Editing or deleting already-posted content.** Out of scope (still unsupported
  per `replying.md`). The "Edit" affordance here edits *unsent* drafts/failed
  items only.
- **Optimistic injection of a new post into a community feed.** Feeds are
  server-paginated/sorted; injecting at the right position is fragile and
  low-value. The post's optimistic home is its pending detail screen, not the
  feed.
- **Private messages.** `ComposerTarget.privateMessage` keeps today's behavior;
  it can adopt this machinery later (the store has room) but is not built now.
- **Guaranteed exactly-once delivery.** Lemmy's `createComment`/`createPost` are
  not idempotent and carry no client dedup token; we mitigate duplicates
  best-effort (see Reconciliation & dedup) but cannot fully eliminate the
  rare "response lost after the server committed" duplicate.

## UX design — three layers

The design is three layers, each solving a different moment. The same mental
model covers comments and posts: *content you create becomes a pending item that
shows instantly, sends durably, and is always recoverable.*

### Layer 1 — instant, in-context optimism

**Comment.** On Post, the composer sheet dismisses immediately and the comment
appears in the tree at its real position (top-level under the post header, or
nested under its parent), rendered with the normal comment body but in a
**pending visual state**: slightly dimmed, a `⟳ Sending…` status line in place of
the score/age metadata, and no vote/save/reply actions yet. On success the row
becomes a normal comment (the real server comment replaces the pending node
seamlessly). On failure the status line flips to `⚠ Failed — tap to retry`;
tapping offers **Retry / Edit / Discard**.

**Post.** On Post, the composer dismisses and the app pushes a **pending
post-detail screen** built from the local draft: it renders the title/body/url
through the normal post-detail header, with a `⟳ Sending…` banner where the
counters/toolbar will be and no comment section. On success the pending screen is
**replaced in the navigation stack** by the real post-detail screen for the new
post (animated off), so it looks like the page simply "became real" — toolbar,
counters, and comment composing now work. On failure the banner flips to
`⚠ Failed` with **Retry / Edit / Discard** buttons.

### Layer 2 — durable background send

The send is a row in a persisted queue, processed by a per-account background
actor that:

- retries transient failures with exponential backoff,
- auto-resumes the whole queue when the network returns (reachability-driven),
- resumes pending/failed sends on the next app launch.

You can leave the pending post screen or the thread; the send keeps going.

### Layer 3 — one recovery home ("Drafts & Outbox")

Because you can navigate away from Layer 1, there is a single list of everything
in flight: a **Drafts & Outbox** screen grouped as **Failed** (actionable, top),
**Sending**, and **Drafts**. Each entry shows kind, target ("Reply in <post
title>", "Post to <community>"), a snippet, status, and **Retry / Edit /
Discard**. Edit reopens the matching composer prefilled.

Discoverability (v1):
- The global failure toast (`Couldn't post — Retry / View`) "View" action opens
  this list. (Reuses the existing outbox failure-toast plumbing.)
- A "Drafts & Outbox" row in the account/preferences area.
- *Nice-to-have, not required:* a small badge on the feed compose button when the
  account has any outbox/draft items.

### Dismiss behavior (Mail-style)

Dismissing a composer with non-empty content presents the standard iOS choice —
**Save Draft** (keep) / **Delete Draft** (discard). An empty composer dismisses
silently. Successfully posting consumes the draft (its row transitions to the
send queue — see below). This resolves the keep-vs-discard tension and matches
Apple Mail/Messages.

## Architecture

### One durable store: `outboundContent`

A single GRDB table holds **both** drafts and in-flight/failed sends as one
lifecycle. One row = one composition.

Lifecycle (`status`): `draft → queued → sending → (deleted on success | failed)`.
`failed` can return to `queued` via retry. There is no `sent` status — a
successful send deletes the row (the real server content lives in
`post`/`comment` tables).

```
outboundContent
  id                     INTEGER PK
  clientToken            TEXT NOT NULL UNIQUE   -- UUID; stable idempotency/dedup key
  accountId              INTEGER NOT NULL        -- FK accountRecord, ON DELETE CASCADE
  kind                   INTEGER NOT NULL        -- 0=comment, 1=post
  status                 INTEGER NOT NULL        -- 0=draft,1=queued,2=sending,3=failed
  draftKey               TEXT NOT NULL           -- per-target dedup key (see below)
  body                   TEXT NOT NULL DEFAULT ''-- comment content / post body markdown
  -- comment target:
  postServerId           INTEGER                 -- the post being replied to
  parentCommentServerId  INTEGER                 -- nil = top-level comment
  -- post target:
  communityServerId      INTEGER
  title                  TEXT
  url                    TEXT
  nsfw                   INTEGER NOT NULL DEFAULT 0
  postType               INTEGER NOT NULL DEFAULT 0 -- text/link/image (UI restore only)
  -- send bookkeeping:
  attempts               INTEGER NOT NULL DEFAULT 0
  lastError              TEXT
  nextAttemptAt          DOUBLE                  -- backoff schedule
  createdAt              DOUBLE NOT NULL
  updatedAt              DOUBLE NOT NULL
```

**Per-target draft uniqueness.** `draftKey` is a normalized string computed at
write time, avoiding SQLite's "NULLs are distinct" unique-index pitfall:
- comment: `"c:<postServerId>:<parentCommentServerId | 0>"`
- post: `"p:<communityServerId | 0>"`

A **partial unique index** on `(accountId, draftKey) WHERE status = 0` (draft)
enforces one *draft* per target. Once submitted (status ≥ queued), the row leaves
the draft index, so you may have several in-flight sends to the same target.

Migration: **`v18_outboundContent`** (next case in
`AppDatabase+Migrations.swift`; the current head is `v17_pendingOperation`).
Records live in `SpudDataKit/Services/AppDatabase/Records/OutboundContentRecord.swift`.
Write/read helpers in `OutboundContentWrites.swift` / `OutboundContentObservations.swift`
(mirroring the existing `PendingOperationWrites.swift` and `*Observations.swift`
conventions; observations use `.async(onQueue: .global(qos: .userInitiated))`).

### Why not reuse `OutboxService`/`pendingOperation`

The existing outbox (vote/save/hide, v17) models **idempotent absolute-state
mutations**: it coalesces per `(account, entity, kind)`, keeps a `baseline`, and
on permanent failure **rolls back to baseline**. Content creation is the
opposite: each submission is a unique, non-idempotent new entity with no prior
state, and on permanent failure we must **keep** the content, not roll it back.
So composing gets its own table and engine. It **shares the plumbing**, not the
schema: reachability monitoring (`ReachabilityMonitoring`), failure
classification (`OutboxFailureClass.classify`), backoff (`backoffDelay`), and the
failure-toast surface are factored to be reused by both.

### The send engine: `ComposerOutboxService`

A per-account actor mirroring `OutboxService`'s shape:

```
protocol ComposerOutboxServiceType: Actor {
    func saveDraft(_ draft: OutboundDraft) async            // upsert status=draft by draftKey
    func submit(clientToken: String) async                  // draft/failed -> queued, then drain
    func retry(clientToken: String) async                   // failed -> queued, reset schedule, drain
    func discard(clientToken: String) async                 // delete row
    func drainOnce() async
    func drainAll() async                                    // reachability-regain / launch
    func start() async                                       // wire reachability, resume on launch
    var failureEvents: AsyncStream<ComposerOutboxFailure> { get }
}
```

Drain loop (per due row, `status ∈ {queued, failed}` with `nextAttemptAt ≤ now`):
1. mark `sending`,
2. call `LemmyService.createComment(...)` or `createPost(...)` — **the existing
   methods**, which already mirror the server response into `comment`/`post`,
3. **success:** delete the outbound row (in the same write that the mirror lands,
   so the pending node and the real content never both show),
4. **transient failure:** `status = failed`, `attempts += 1`,
   `nextAttemptAt = now + backoff(attempts)`, keep `lastError`,
5. **permanent failure:** `status = failed` (kept, *not* deleted/rolled back),
   record `lastError`, emit a `failureEvents` event for the toast.

The key behavioral difference from `OutboxService`: **permanent failure parks the
row as `failed` and keeps the content.** Manual `retry` re-queues it.

`start()` is called per account at app launch / account-ready (alongside
`OutboxService.start()`), so prior-launch `queued`/`failed` rows resume and
reachability transitions trigger `drainAll()`.

### Rendering the optimistic comment (overlay, not schema pollution)

The comment tree is built by `observePostDetailComments(postRowId, sortType) ->
[PostDetailCommentRow]`, snapshotted via `visibleCommentTree()`. Rather than
inserting fake `CommentRecord`s (nullable server id, pending flags) into the
schema, the post-detail view model **overlays** outbound rows at render time:

- A second observation, `observeOutboundComments(postServerId) ->
  [OutboundContentRow]`, streams this post's pending/failed comment rows.
- The view model merges: build the real tree, then splice each outbound comment
  as a synthetic pending node — as a child of the loaded row whose
  `serverCommentId == parentCommentServerId`, or at top level when
  `parentCommentServerId == nil`.
- Pending nodes render via a dedicated cell configuration (dimmed body +
  `Sending…`/`Failed` status line + tap actions). They are keyed in the diffable
  snapshot by `clientToken` (distinct from real `.comment(elementId:)` items).

On success the outbound row is deleted and the real `CommentRecord` is already
present (via the `createComment` mirror) → the pending node vanishes, the real
node appears, no flicker. If the parent of a pending reply isn't in the loaded
page (rare), the pending node falls back to top-level placement with its indent
preserved.

### Rendering the optimistic post (replace-on-success)

A small, focused **`PendingPostViewController`** renders the optimistic post from
an outbound row (`clientToken`): title/body/url through the shared post-detail
header view, a `Sending…`/`Failed` banner, no toolbar/comments. It observes its
own outbound row. On success — when `createPost`'s mirror has produced the real
`PostRecord` (we learn its `postRowId`/`serverPostId`) — it asks the coordinator
to **replace itself** in the navigation stack with the real `PostDetailViewController`
(`setViewControllers`, non-animated) for a seamless "became real" transition. If
the user already navigated away, nothing swaps; the durable queue + toast + Drafts
& Outbox still surface the result.

### Reconciliation & dedup (the non-idempotent hazard)

`createComment`/`createPost` are not idempotent and Lemmy gives us no client
token to echo. Mitigations, in order:

1. **Normal path:** the outbound row is deleted on the success response, so no
   duplicate arises.
2. **Reconciliation guard in importers:** `CommentImporter`/post import already
   guard against clobbering pending outbox state; extend the same idea so a
   server comment/post that matches an outbound row is treated as that row's
   realization.
3. **Dedup-on-reconcile heuristic (backstop for "response lost after commit"):**
   when a tree/feed refresh imports a comment/post authored by the current
   account that matches an outbound row by `(parentCommentServerId |
   communityServerId, trimmed body, recent createdAt window)`, adopt it — delete
   the outbound row instead of leaving a duplicate pending node, and don't retry
   that row. This catches the timeout-after-commit case.

Residual risk: a duplicate can still occur if the server commits, the response is
lost, *and* no subsequent refresh import matches before an auto-retry fires. This
is documented as a known limitation, not silently ignored.

### Draft autosave

The composer view models (`ComposerViewModel`, `NewPostViewModel`) gain a
reference to `ComposerOutboxServiceType` (injected like other services):

- **On open:** load the draft for the target's `draftKey`; if present, silently
  prefill (caret at end). Pre-fill of launch context (e.g. community from a
  community screen) still applies when there is no saved draft.
- **While editing:** debounce field changes (~1.5s idle) and write/update the
  draft row; also flush on `viewWillDisappear`, `UIScene` background, and
  `resignActive`.
- **On Post:** the draft row transitions to `queued` (same row — no duplicate),
  the composer dismisses, and Layer-1 optimism takes over.
- **On dismiss with content:** Mail-style Save Draft / Delete Draft.
- **On successful send:** row deleted by the engine.

## Data flow (comment, happy path)

```
type → debounce → outboundContent(status=draft) written
tap Post → row.status=queued; sheet dismisses
         → tree overlay shows pending node (Sending…)
ComposerOutboxService.drain → LemmyService.createComment
         → server CommentView mirrored into `comment` table
         → outbound row deleted (same write)
tree observation refires → pending node gone, real comment present
```

## Error handling & retry policy

- **Classification** reuses `OutboxFailureClass.classify(error, isOnline:)`:
  network/5xx/429/timeout → transient; auth/validation/permission (e.g. parent
  deleted, community banned, post locked) → permanent.
- **Backoff** reuses `backoffDelay(attempts:)` (2s, doubling, capped 300s).
- **Auto-retry** for transient until connectivity/backoff allow; **no attempt
  cap that discards** — a row that keeps failing parks as `failed` and waits for
  manual action. (We may stop *automatic* retries after N attempts but always
  keep the row.)
- **Permanent failure** parks as `failed` immediately + global toast.
- **Signed-out:** submit is gated at the compose entry (existing "Sign in to
  post/comment" alert). Drafts may still be saved locally; submit requires
  sign-in.

## Edge cases

- **Parent comment / post deleted or locked before send** → permanent failure,
  parked `failed` with a clear message; user discards or edits.
- **Account logout/removal** → outbound rows cascade-delete with the account
  (consistent with other per-account data; drafts are lost on full removal — an
  accepted trade-off).
- **Multiple sends to the same target** → allowed (draft uniqueness only
  constrains `status=draft`).
- **Pending reply whose parent isn't on the loaded page** → top-level fallback
  placement with indentation preserved.
- **App killed mid-`sending`** → on launch, `start()` re-drains; a row stuck in
  `sending` is treated as due (re-queued). The dedup heuristic guards against a
  double-create if the prior attempt actually committed.

## Testing

Unit (`SpudDataKitTests`, Swift Testing; in-memory `AppDatabase` + fake
performer, mirroring `OutboxService` tests):
- draft upsert keyed by `draftKey` enforces one draft per target; non-draft rows
  unconstrained.
- lifecycle transitions: draft→queued→(deleted|failed), failed→queued on retry.
- transient vs permanent classification routing; backoff scheduling.
- permanent failure **keeps** the row (contrast with outbox rollback).
- dedup-on-reconcile: matching imported content adopts (deletes) the outbound
  row; non-matching does not.
- `v18` migration creates table + partial unique index.

Snapshot (`SpudSnapshots`, iPhone 14 Pro portrait):
- pending comment cell (`Sending…`), failed comment cell (`Failed — tap to
  retry`), light + dark.
- pending post-detail (`Sending…` banner) and failed pending post, light + dark.
- Drafts & Outbox list with Failed/Sending/Drafts groups.

UI (`SpudUITests`): post a comment offline (stubbed failure) → pending node
appears → retry succeeds path. (Mind the one-booted-sim flake note.)

## Files (anticipated)

New (SpudDataKit):
- `Services/AppDatabase/Records/OutboundContentRecord.swift`
- `Services/AppDatabase/OutboundContentWrites.swift`
- `Services/AppDatabase/OutboundContentObservations.swift`
- `Services/Outbox/ComposerOutboxService.swift` (+ `ComposerOutboxServiceType`,
  failure type)
- shared helpers extracted from `OutboxService` (classification/backoff/
  reachability) if cheap; otherwise minimal duplication
- `AppDatabase+Migrations.swift`: `v18_outboundContent`

New (Spud):
- `Scenes/Composer/PendingPostViewController.swift`
- `Scenes/DraftsOutbox/OutboundContentListViewController.swift` (+ view model)
- pending comment cell configuration (extend the post-detail comment cell)

Modified (Spud):
- `ComposerViewModel` / `NewPostViewModel`: draft load/save, submit→enqueue,
  Mail-style dismiss.
- `ComposerViewController` / `NewPostViewController`: dismiss confirmation, no
  more blocking spinner on submit.
- `PostDetailViewController` / its view model: outbound-comment overlay + pending
  cell + tap actions.
- `AppCoordinator`: push pending post detail; replace-on-success; "View" from
  toast → Drafts & Outbox.
- failure-toast presenter: also consume `ComposerOutboxService.failureEvents`.

`make project` (XcodeGen) after adding files.

## Docs to update on completion

- `docs/features/draft-persistence.md` — from "in-memory only" to durable,
  per-target, auto-saved, with the Drafts & Outbox surface.
- `docs/features/replying.md` — optimistic inline comment + durable retry.
- `docs/features/new-post.md` — pending post-detail + durable retry.

## Rollout / phasing (for the implementation plan)

1. **Store + engine (headless):** `v18` table, record, writes/observations,
   `ComposerOutboxService` with reachability/backoff/dedup, unit tests. No UI
   change yet (submit can route through it invisibly).
2. **Comment optimism:** draft autosave in `ComposerViewModel`, tree overlay +
   pending cell + tap actions, snapshots.
3. **Post optimism:** draft autosave in `NewPostViewModel`,
   `PendingPostViewController` + replace-on-success, snapshots.
4. **Recovery surface:** Drafts & Outbox list, toast "View" wiring,
   Mail-style dismiss, entry points.
5. **Docs refresh.**

## Open risks

- **Duplicate sends** on lost-response-after-commit (mitigated, not eliminated).
- **Pending-post → real-post navigation swap** is the most delicate UI seam;
  isolating it in `PendingPostViewController` + a coordinator replace keeps it
  contained.
- **Shared-plumbing extraction** from `OutboxService` must not regress the
  shipped vote/save/hide outbox; if extraction looks risky, prefer minimal
  duplication.
