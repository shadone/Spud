# Removed / unavailable content handling — design

Date: 2026-07-04
Status: Approved (pending implementation plan)
Scope: Posts. Detect when a post no longer exists server-side, mark it locally, and surface it honestly on the post-detail screen and in the feed, instead of showing stale content that silently fails on interaction. Comment-level "removed/deleted" already works and is out of scope.

## Problem

A spam/scam post can enter a user's feed and then be removed on its origin
instance (moderator takedown) or deleted by its author. The user's home
instance still holds a stale federated copy, so:

- Tapping the post opens the detail screen and it renders "as if all is well"
  — the cached copy shows normally, because it was cached with
  `removed = false` and nothing re-checks.
- Voting on it shows a generic **"Couldn't vote"** toast. The underlying error
  is `serverError(ErrorResponse(error: "couldnt_find_post"))`, correctly
  classified as a permanent failure and rolled back (`op.permanentRollback`),
  but the message tells the user nothing about *why*, and the stale cache is
  never reconciled.
- Opening the *same* kind of post via a deep link (not cached) leaves the
  loading spinner running **forever** — the `getPost` error is swallowed and
  no row ever appears.

The app never tells the user "this post is gone," and never updates its local
state to reflect reality.

## What exists today

**The data model is already in good shape.**

- `PostRecord` stores `isRemoved`, `isDeleted`, `isLocked`, `isFeaturedCommunity`,
  `isFeaturedLocal` (`SpudDataKit/Services/AppDatabase/Records/Post.swift:48`).
  `CommentRecord` has the analogous `isRemoved` / `isDeleted` / `removedReason`.
- `PostImporter.apply(view:to:now:)` copies `post.removed` / `post.deleted`
  from the Lemmy `PostView` into the record
  (`SpudDataKit/Services/AppDatabase/Importers/PostImporter.swift:203`).
- `PostStatusBadge` renders removed (red `trash.slash.fill`), deleted (red
  `trash.fill`), featured (green `pin.fill`), locked (yellow `lock.fill`), with
  that priority (`Spud/Scenes/Shared/PostStatusBadge.swift:39`). It is wired
  into the **feed cell** only (`PostListPostViewModel.swift:289`), **not** the
  post-detail header.
- Comments already render "Comment deleted by author" / "Removed by moderator"
  placeholders (`PostDetailCommentViewModel.swift:235`) — the template this
  design follows for posts.

**The vote-failure path is mechanically correct but semantically blind.**

- `OutboxFailureClass.classify` treats any `serverError(errorResponse)` as
  **permanent** unless it is `rate_limit*`
  (`SpudDataKit/Services/Outbox/OutboxFailureClass.swift:54`). `couldnt_find_post`
  is therefore permanent — correct.
- `OutboxService` rolls the vote back to baseline and emits an `OutboxFailure`
  (`OutboxService.swift:219`). `MainWindow` maps `kind == .vote` to the generic
  `NSLocalizedString("Couldn't vote")` toast (`MainWindow.swift:365`). The
  failure event carries no reason, so the message can't be specific.

**The read paths swallow or mis-classify the "gone" signal.**

- `PostDetailLoadingViewController.fetchPostInfo()` catches the error and calls
  `alertService.handle(error, for:)` (log-only), then `notifyIfRowAvailable()`;
  if no row lands, the spinner hangs
  (`Spud/Scenes/PostDetail/Loading/PostDetailLoadingViewController.swift:129`).
- Opening a cached post does **not** call `getPost`. It renders cached data and
  fetches only comments (`viewModel.fetchComments()` in `viewDidLoad`,
  `PostDetailViewController.swift:416`). `getPost` runs only on pull-to-refresh
  (`refreshPostInfo()` swallows its error, `:1256`).
- `LoadFailure.classify` buckets every `serverError` as `.unreachable`
  (`SpudDataKit/Services/Lemmy/LoadFailure.swift:113`) — so a removed post reads
  as a network problem, and comment loads on a removed post show "Couldn't reach
  server."

### Gaps that produce the symptoms

1. No local concept of "the server 404'd this post." `isRemoved`/`isDeleted`
   only get set when the server *returns* a post object saying so; a
   `couldnt_find_post` **error** sets nothing.
2. The `getPost` / `fetchComments` "not found" error is swallowed or
   mis-classified as unreachable.
3. The outbox rollback doesn't reconcile local state or explain the failure.
4. The post-detail header shows no removed/unavailable treatment for non-mods.
5. The deep-link loading path has no terminal "not found" state — it hangs.

## Decisions (anchors)

1. **A distinct local `isUnavailable` flag**, separate from
   `isRemoved`/`isDeleted`. `isRemoved`/`isDeleted` mean "the server returned the
   post and told us so." `isUnavailable` means "the server rejected the request
   with `couldnt_find_post` and we don't know why." Keeping them separate is what
   lets the wording stay honest: neutral for the ambiguous case, specific when we
   actually know.
2. **One shared not-found classifier** — a single source of truth for the
   `couldnt_find_post` string match, mirroring `OutboxFailureClass` /
   `LoadFailure`.
3. **Converge every touchpoint to one DB write.** Read paths (`getPost`,
   `getComments`) and the outbox rollback all funnel a not-found signal into a
   single idempotent `markPostUnavailable`. The UI (feed cell + detail) reacts to
   the flag via the existing GRDB observations.
4. **Detail screen replaces with a placeholder** ("this post is no longer
   available"), gated so moderators and authors keep visibility of their own /
   removable content.
5. **Feed badge is neutral (gray), not red.** For the ambiguous
   `couldnt_find_post` case we don't assert "removed"; the existing red
   Removed/Deleted badges stay for the cases where the server actually says so.
6. **Recovery is automatic.** A fresh authoritative `PostView` clears
   `isUnavailable` (restore / re-federation heals the local state).

## Architecture

### Shared components (SpudDataKit)

**`ContentNotFound`** — a pure classifier.
`ContentNotFound.matches(_ error: Error) -> Bool` returns `true` when the error
is a Lemmy structured rejection whose `error` string is a post-not-found code
(`couldnt_find_post`, plus siblings such as `couldnt_find_object` if present),
unwrapping both `LemmyServiceError.apiError(.serverError(...))` and a bare
`LemmyApiError.serverError(...)`. It is the only place the string appears. Unit
tested in isolation.

**`PostRecord.isUnavailable: Bool`** — new persisted column, default `false`.
- Migration **`v28_postUnavailable`** adds the column (v27_voteEvent is the
  current latest; CLAUDE.md's "next is v27" is stale). Follows the existing
  `ALTER TABLE post ADD COLUMN ... NOT NULL DEFAULT 0` migration pattern; no
  edits to prior migrations.
- `AppDatabase.markPostUnavailable(forKeychainId:serverPostId:)` — idempotent
  write that sets `isUnavailable = true`.
- `PostImporter.apply(view:...)` sets `record.isUnavailable = false` — a real
  `PostView` means the post is back.

**Observation plumbing.** Add `isUnavailable` to `PostDetailHeaderRow`
(`PostDetailObservations.swift`) and `PostListRow` (`PostListObservations.swift`)
and their SELECTs, so both the detail header and the feed cell see the flag.

### Marking on every touchpoint

- **Read paths** — in `LemmyService.fetchPostInfo` and `fetchComments`, on a
  `ContentNotFound` error, call `markPostUnavailable` before rethrowing. This
  keeps detection out of the view controllers and DRY.
- **Outbox path** — in `OutboxService`'s permanent-rollback branch, when the
  rolled-back operation targets a post and `ContentNotFound.matches(error)`,
  call `markPostUnavailable`. Extend `OutboxFailure` with `reason: Reason`
  (`.notFound` | `.other`) so the toast can be specific.

### Detail screen (Spud)

**`PostUnavailableViewController`** — a shared centered placeholder (SF Symbol +
title + subtitle), reused by both the loading and content paths. Message chosen
by a `Reason`:
- `.unavailable` → "This post is no longer available" / "It may have been
  removed."
- `.removed` → "Removed by moderator".
- `.deleted` → "Deleted by author".

**`PostDetailOrEmptyViewController`** gains a `case unavailable(reason:)` in its
`State` enum, rendering `PostUnavailableViewController`.

Transitions:
- **Deep-link (`.load`)**: `PostDetailLoadingViewController` gets a
  `didFail: ((Reason) -> Void)?` callback. On a `ContentNotFound` error from
  `fetchPostInfo`, it fires `didFail(.unavailable)` → parent sets
  `state = .unavailable(...)`. Fixes the infinite spinner.
- **Cached (`.post`)**: `PostDetailViewController` observes the header row and
  computes whether the placeholder should show (rule below). When it should, it
  fires a `didBecomeUnavailable: ((Reason) -> Void)?` callback → parent sets
  `state = .unavailable(...)`.

**Visibility gating** (a computed property on the header row / view model, so it
is unit-testable). Show the placeholder unless the user should keep seeing the
content:
- `isDeleted && ownPost` → keep today's dimmed content + Restore. Not a
  placeholder.
- `isRemoved && canModerate(community)` → keep content + mod Restore. Mods must
  still see removed posts.
- else `isRemoved` → placeholder `.removed`.
- else `isDeleted` → placeholder `.deleted`.
- else `isUnavailable` → placeholder `.unavailable`.

`canModerate` is already available in the detail VC
(`moderationCapability.canModerate(communityId:)`); "own post" is derivable from
the header row's creator vs. the account.

### Feed cell (Spud)

Extend `PostStatusBadge` with an `unavailable` case: a **neutral gray** symbol
(`exclamationmark.octagon`) with `.secondaryLabel` tint, shown when
`isUnavailable && !isRemoved && !isDeleted`. Priority becomes
removed > deleted > unavailable > featured > locked. Feeds `isUnavailable`
through the `PostListRow` added above.

### Interaction toast (Spud)

`MainWindow`: when `OutboxFailure.reason == .notFound`, show
`NSLocalizedString("This post is no longer available")` instead of "Couldn't
vote" / the save/hide equivalents. Still fires from feed swipe-votes (where
there is no detail screen to swap), alongside the new feed badge.

## Data flow

```
                       couldnt_find_post
   ┌─ getPost ─────────────┐
   │  (pull-to-refresh)     │
   ├─ getComments ─────────┤
   │  (open / sort / retry) ├──► ContentNotFound.matches ──► markPostUnavailable
   ├─ vote/save/hide ──────┘        (one classifier)          (isUnavailable = true)
   │  (outbox rollback)                                              │
   │                                                                 ▼
   │                                          GRDB observation (PostDetailHeaderRow,
   │                                                            PostListRow)
   │                                                                 │
   │                        ┌────────────────────────────────────────┼───────────────┐
   ▼                        ▼                                         ▼               ▼
 outbox failure       PostDetailOrEmpty                        PostList cell     (later:
 reason=.notFound  →  gating rule → .unavailable(reason)  →    neutral badge     restore
   → specific toast    → PostUnavailableViewController                            heals via
                                                                                  PostView →
                                                                        isUnavailable = false)
```

## Error handling

- `ContentNotFound` matches **only** the post-not-found rejection codes; every
  other error keeps today's behavior (offline / unreachable / malformed
  buckets, generic toasts). Rate-limit and transient errors are untouched — they
  never mark a post unavailable.
- `markPostUnavailable` is idempotent and a no-op if the row is absent (deep-link
  case has no row; the placeholder comes from the loading callback instead).
- Recovery: any subsequent successful `PostView` import clears the flag, so a
  restored or re-federated post returns to normal in both feed and detail.

## Testing

Unit (Swift Testing):
- `ContentNotFound`: `couldnt_find_post` → true; unrelated `serverError`,
  `rate_limit*`, `URLError`, decode error → false.
- `markPostUnavailable` sets the flag; `PostImporter.apply(view:)` clears it
  (restore recovery).
- `OutboxFailureClass` unchanged (still permanent); outbox rollback with a
  not-found error marks the post and emits `reason == .notFound`.
- `PostStatusBadge`: `unavailable` case + priority ordering.
- Detail placeholder gating: own-deleted → keep content; mod + removed → keep
  content; other + removed → `.removed`; unavailable → `.unavailable`.

Snapshot (record on iPhone 17 Pro, iOS 26.3):
- `PostUnavailableViewController` for the three reasons.
- Feed cell with the neutral unavailable badge.

Deferred / optional:
- A UITest that stubs `getPost` (or a vote) → `couldnt_find_post`, opens the
  post, and asserts the placeholder appears. Feasible via XCUITest; noted, not
  required for the first cut.

## Docs

- New `docs/features/removed-unavailable-content.md` with Given/When/Then
  scenarios (open a removed cached post; vote on a removed post from the feed;
  deep-link to a removed post; moderator opens a removed post; author opens own
  deleted post; restore heals).
- Update `docs/features/README.md` capability table **and** the "Feature
  coverage by area" map.
- Reconcile adjacent docs: `empty-error-loading-states.md`,
  `feed-loading.md`, `mark-read-and-hiding.md`, and any moderation doc that
  mentions removed content.

## Out of scope / non-goals

- Comment-level removed/deleted handling (already implemented).
- Hiding or auto-removing the post from the feed — we badge, not delete (user
  decision).
- Distinguishing removed-vs-deleted for the ambiguous `couldnt_find_post` case —
  we say "no longer available" and only use specific wording when the server
  actually returns `removed`/`deleted`.
- A dedicated modlog fetch to obtain a removal reason for posts (comments get
  theirs from an existing modlog path; posts can follow later if wanted).
