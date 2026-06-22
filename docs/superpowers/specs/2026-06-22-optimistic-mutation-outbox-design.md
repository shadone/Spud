# Optimistic mutation outbox (vote / save / hide)

Date: 2026-06-22
Status: Approved — ready for implementation planning
Branch: `feat/optimistic-mutation-outbox`

## Problem

Voting on a post or comment feels laggy. Today the UI blocks on the network
round-trip before the vote is reflected:

```
tap/swipe
  -> LemmyService.vote(...)            (actor)
       reads current voteStatus from GRDB
       await api.likePost/likeComment  (BLOCKS on network)
       mirror response -> GRDB upsert
  -> ValueObservation fires -> UI finally repaints
```

There is no optimistic update, no retry, and no rollback. A failed vote is
only logged (`alertService.handle(error, for: .vote)`); the user gets no
feedback and the vote is silently lost. The same blocking pattern applies to
save and hide.

## Goal

Apply the user's mutation to the UI immediately while the network request runs
in the background, with a durable retry queue that survives app kill, retries
transient failures, and rolls back only on permanent rejection.

This is built as a **generic outbox for idempotent set-state mutations**, with
**vote, save, and hide** all wired through it in this spec. The durable-queue
substrate is factored so a future Drafts feature can reuse it; drafts
themselves are out of scope (see Non-goals).

## Decisions (locked during brainstorming)

- **Durability**: persisted queue in a new GRDB table; survives app kill and
  enables offline mutations, retried on next launch / reconnect.
- **Retry policy**: distinguish transient vs permanent errors. Transient
  (offline, timeout, 5xx, 429) retry forever; permanent (auth, 4xx, gone) roll
  back the optimistic state and surface it.
- **Failure surface**: subtle, non-blocking toast on permanent failure
  ("Couldn't vote / save / hide"); the optimistic state silently reverts.
- **Scope now**: generic outbox machinery + vote + save + hide. Drafts kept
  separate.
- **Toggle-to-baseline optimization**: kept (rapid on/off sends nothing).

## Why these three kinds share one abstraction

`likePost(status:)`, `savePost(save:)`, `hidePost(hide:)` (and the comment
equivalents) are all **idempotent set-state** calls — each sends an absolute
desired state, so retrying is safe. Each projects onto an existing local field,
coalesces per `(account, target, kind)` to a final desired state, and rolls
back to a baseline on permanent failure.

Drafts (composing a comment/post/PM) are a **create**, not a set-state: they
yield a new server entity with a new id (needs an idempotency key to avoid
duplicates on retry), have no field to project onto (insert a provisional local
entity that adopts the real id on success), can be edited while pending, and on
failure are kept (not rolled back). They share only the durable-queue substrate,
not the projection/coalesce/rollback model — hence a separate future feature.

## Current seams (verified)

| Kind | Entry point (`LemmyService`) | API call | Returns | Local fields | Entities |
|---|---|---|---|---|---|
| vote | `vote(serverPostId:vote:)` / `vote(serverCommentId:vote:)` | `api.likePost/likeComment(status:)` | full `PostView` / `CommentView` | `voteStatus`, `score`, `numberOfUpvotes`, `numberOfDownvotes` | post, comment |
| save | `setSaved(serverPostId:saved:)` / `setSaved(serverCommentId:saved:)` | `api.savePost/saveComment(save:)` | full `PostView` / `CommentView` | `isSaved` | post, comment |
| hide | `hidePost(serverPostId:hidden:)` | `api.hidePost(postIDs:hide:)` | `SuccessResponse` (no entity) | `isHidden` | post only |

Notes:
- `LemmyService` is a per-account `actor` holding the authed `api` client.
- Vote encoding in GRDB: `voteStatus` `1` = up, `0` = down, `nil` = none.
  `VoteStatus.effectiveAction(for:)` already computes the absolute
  `LikeStatus` (`.liked` / `.disliked` / `.neutral`) from current state + tap.
- Vote/save mirror a full returned view via `mirrorPostInfoToAppDatabase` /
  `mirrorCommentToAppDatabase`. **Hide returns no entity** — its success
  reconcile is a no-op (the optimistic write stands).
- UI reads all of these fields purely through GRDB `ValueObservation`
  (`PostListObservations`, `PostDetailObservations`), so an optimistic DB write
  repaints instantly.
- Targeted-write precedent already exists: `appDatabase.setPostIsHidden(...)`.
- `ReachabilityMonitoring` (with `isOnline` + `statusStream`) already exists.
- A feed-loading failure classifier (`LoadFailure`) already exists to reuse.
- No toast surface exists yet — net-new.
- Next GRDB migration slot is `v17`.
- Signed-out is already gated in `setSaved` / `hidePost` (throws
  `requiresAuthentication`); votes currently are NOT gated — this spec adds the
  gate so we never optimistically apply then rip away.

## Architecture

A new per-account **`OutboxService`** actor in `SpudDataKit` owns a durable
queue of pending mutations and drains them in the background.

```
tap/swipe
  -> LemmyService.vote/setSaved/hidePost(...)   (unchanged signatures)
       signed-out gate (throws requiresAuthentication if signed out)
       -> OutboxService.enqueue(operation)
            1. snapshot baseline (only if no pending row for this kind+target)
            2. applyOptimistic -> targeted GRDB delta write  (UI repaints NOW)
            3. upsert pending row (coalesce)
            4. kick drain loop (non-blocking)
       returns immediately
  ~ background ~
  drain loop -> send(api:) -> success | transient | permanent
```

`LemmyService` constructs and holds its account's `OutboxService` (sharing the
same `api`, `appDatabase`, and `ReachabilityMonitoring`) and delegates. Call
sites keep calling `lemmyService.vote/setSaved/hidePost(...)` — no signature
change; they only get simpler (drop the network `do/catch`).

### Operation model

- `OutboxEntity` = `.post(PostID)` | `.comment(CommentID)`
- `OutboxKind` = `.vote` | `.save` | `.hide`
- `OutboxOperation` = entity + kind + **desiredState** (absolute: vote →
  liked/disliked/neutral; save → bool; hide → bool)

Each kind is a small strategy providing:
- `applyOptimistic` — write the local projection (delta-based for vote;
  field set for save/hide)
- `rollback` — inverse of what was applied (using the stored baseline)
- `send(api:)` — the LemmyKit call with the absolute desired state
- `reconcile` — vote/save mirror the returned view; **hide is a no-op confirm**

Adding a future kind = one more strategy. Sendable value types; the actor
selects the strategy by `kind`.

## Data model — `pendingOperation` table (migration `v17`)

| column | type | purpose |
|---|---|---|
| `id` | INTEGER PK | autoincrement |
| `accountId` | INTEGER FK | per-account scoping |
| `entityType` | TEXT | `post` \| `comment` |
| `entityServerId` | INTEGER | Lemmy post/comment id |
| `kind` | TEXT | `vote` \| `save` \| `hide` |
| `desiredState` | TEXT/INT | absolute target to send |
| `payload` | TEXT (JSON) | kind-specific rollback baseline: prior `voteStatus` + net applied `score`/`upvote`/`downvote` deltas (vote), or prior bool (save/hide) |
| `attempts` | INTEGER | retry count |
| `lastError` | TEXT? | last failure description |
| `nextAttemptAt` | REAL? | backoff schedule (epoch seconds) |
| `createdAt` | REAL | ordering |
| `updatedAt` | REAL | ordering |

`UNIQUE(accountId, entityType, entityServerId, kind)` → coalescing per op-kind
per target. Vote and save on the same post are different kinds → two
independent rows. Two rapid upvotes collapse to one row.

## Lifecycle

### Enqueue (one GRDB transaction)

1. If no pending row exists for `(account, entity, kind)`, snapshot the current
   local projected state as the rollback baseline into `payload`.
2. `applyOptimistic`: targeted delta writes —
   `setPostVote` / `setCommentVote` (apply `score`/`upvote`/`downvote` deltas +
   set `voteStatus`), `setSaved`, `setHidden`. Accumulate vote deltas into
   `payload` so rollback can subtract them.
3. Upsert the pending row (coalesce): update `desiredState`, reset `attempts`
   and `nextAttemptAt = now`, **preserve baseline**.
4. Kick the drain loop.

UI repaints instantly via existing `ValueObservation`.

**Toggle-to-baseline optimization**: if the new `desiredState` equals the
confirmed baseline (e.g. upvote then upvote-off), delete the pending row and
revert the projection to baseline — nothing is sent.

### Drain loop (serial per account)

For each due row (`nextAttemptAt <= now`, oldest first), `send(api:)` with
`desiredState`:

- **Success** → delete the pending row, then `reconcile` (vote/save mirror the
  authoritative returned view; hide leaves the optimistic write as truth).
  Deleting the row *before* reconcile lets the mirror write server truth past
  the reconciliation guard.
- **Transient failure** → keep the row, `attempts++`, set `lastError`,
  `nextAttemptAt = now + backoff(attempts)` (exponential, capped ~5 min).
- **Permanent failure** → `rollback` to baseline (inverse delta / restore
  bool), delete the row, emit a failure event.

### Triggers

- On enqueue.
- On `reachabilityMonitor.statusStream` → `true` (reset backoff, drain now).
- On app launch + foreground (existing `SceneDelegate` / `MainWindow`
  foreground hook).
- Backoff timer for the soonest pending `nextAttemptAt`.

### Startup

Persisted rows already carry their optimistic state in the DB (it was written
at enqueue time), so on launch the service just resumes draining. No re-apply.

## Error classification

Reuse the feed-loading `LoadFailure` classifier + reachability:

- **Transient** (retry forever): offline (`reachability.isOnline == false`),
  URLError timeouts / connection-lost / cannot-connect, HTTP 5xx, 429.
- **Permanent** (rollback + toast): 401/403 (auth), 404/410 (entity gone),
  other 4xx, `requiresAuthentication`.

Signed-out is gated at the `LemmyService` entry *before* the optimistic write,
so it never applies-then-reverts; the call site shows the existing sign-in CTA.

## Reconciliation guard (the delicate part)

A background **refresh** fetch (feed/detail) must not clobber an un-synced
optimistic field. `PostImporter` / `CommentImporter` consult the pending table
on upsert and **preserve** the projected fields for any kind with a pending row:

- vote pending → preserve `voteStatus`, `score`, `numberOfUpvotes`,
  `numberOfDownvotes`
- save pending → preserve `isSaved`
- hide pending → preserve `isHidden`

The outbox success path deletes the pending row first, so its own reconcile
mirror writes server truth unguarded. This is the correctness backbone of the
optimistic UI; without it a refresh mid-flight flickers the optimistic state.
It is the most invasive change (touches the importers) and must be isolated and
tested carefully.

## UI / feedback

- A lightweight, window-level **`ToastPresenter`** in the app target
  (auto-dismiss, non-blocking): "Couldn't vote / save / hide."
- One app-level subscriber (in `AppCoordinator` / `SceneDelegate`) consumes each
  account's `outbox.failureEvents` `AsyncStream` and shows the toast.
  `SpudDataKit` stays UI-free — it emits typed failure events; the app renders.
- Call sites lose their network `do/catch`; they keep the instant haptic and
  the signed-out sign-in CTA.

## Components / files (small-files convention)

SpudDataKit:
1. `AppDatabase+Migrations.swift` — add `v17_pendingOperation`.
2. `Records/PendingOperationRecord.swift` — GRDB record.
3. `Outbox/OutboxOperation.swift` — `OutboxEntity` / `OutboxKind` /
   `OutboxOperation` value types (Sendable) + `desiredState` encodings.
4. `Outbox/OutboxProjection.swift` — pure projection + rollback math (vote
   delta table, save/hide bool). May absorb `VoteStatus+Action`.
5. `Outbox/OutboxService.swift` + `OutboxServiceType` protocol — the actor:
   enqueue, drain, triggers, `failureEvents` stream.
6. `Outbox/OutboxError.swift` — transient/permanent classification (reuse
   `LoadFailure`).
7. `AppDatabase/PendingOperationWrites.swift` — enqueue/coalesce, fetch-due,
   delete, rollback helpers.
8. `AppDatabase/OptimisticWrites.swift` — targeted, delta-aware writes:
   `setPostVote` / `setCommentVote` (apply score/upvote/downvote deltas + set
   `voteStatus`), `setPostSaved` / `setCommentSaved`, and reuse the existing
   `setPostIsHidden` for hide.
9. `Importers/PostImporter.swift` + `CommentImporter.swift` — reconciliation
   guard.
10. `LemmyService.swift` — `vote` / `setSaved` / `hidePost` delegate to the
    outbox; add the vote signed-out gate; keep signatures.
11. Account wiring — construct `OutboxService` per account (with `api` /
    `appDatabase` / `reachabilityMonitor`); expose `failureEvents` via
    `AccountScope`.

Spud app:
12. `Toast/ToastPresenter.swift` — window-level toast.
13. Subscriber wiring in `AppCoordinator` / `SceneDelegate`; drain on foreground.
14. Simplify vote/save/hide call sites (`PostListViewController`,
    `PostDetailViewController`, `MediaViewerViewController`,
    `HiddenAndMutedViewModel`): drop network `do/catch`, keep signed-out CTA.

Tests (SpudDataKitTests):
15. Coverage per the Testing section.

## Testing (TDD)

Against in-memory GRDB + a fake `api` + `StaticReachabilityMonitor` + an
injectable clock:

- Projection/rollback math: all 6 vote transitions (neutral/up/down ×
  liked/disliked/neutral) + save/hide toggles, for both post and comment, write
  correct fields/deltas.
- Enqueue applies the optimistic write and creates the pending row.
- Coalescing: a second op on the same `(account, entity, kind)` yields one row
  with updated `desiredState`, preserved baseline, accumulated vote deltas;
  toggle-to-baseline deletes the row and reverts the projection.
- Independent kinds coexist (vote + save on the same post = two rows).
- Drain success: vote/save mirror the authoritative view and remove the row;
  hide confirms and removes the row (optimistic write stands).
- Drain transient: row kept, `attempts++`, `nextAttemptAt` set; reachability →
  online triggers an immediate drain; backoff schedule respected.
- Drain permanent: rollback to baseline (inverse), row removed, failure event
  emitted.
- Reconciliation guard: a refresh import with a pending op preserves the
  optimistic field; an outbox reconcile (no pending row) writes server truth.
- Signed-out: no optimistic write, `requiresAuthentication` thrown.
- Startup: persisted rows resume draining.

## Non-goals (YAGNI)

- Drafts / message composition — separate future feature. May reuse the
  durable-queue substrate (rows, backoff, reachability drain, classification)
  but not the projection/coalesce/rollback model (creates need idempotency keys,
  provisional entities, edit-while-pending, keep-on-fail).
- General create-semantics in this outbox.
- Cross-account batching UI.
- Conflict resolution beyond last-write-wins + the reconciliation guard.
