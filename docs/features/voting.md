# Voting

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Post detail and comments](post-detail-and-comments.md), [Saving](saving.md), [Sign-in gate on write actions](sign-in-gate.md), [Configurable swipe actions](swipe-actions.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Upvote or downvote any post or comment. A vote is applied **optimistically** — the score and your vote state update immediately in the local store — and is sent in the background through a durable, per-account outbox that retries transient failures and rolls back permanent ones, so the server stays the source of truth. Tapping the same direction you already voted removes your vote. Votes are reachable from the post's action bar, comment swipe slots, and the per-comment context menu.

## Behavior and rules

- **Posts and comments both vote.** The post header has inline upvote / downvote buttons; comments expose Upvote and Downvote through their context menu and through their swipe slots.
- **Optimistic, via the durable outbox.** A vote is written to the local database synchronously at enqueue time (before any network call), so the score and highlight change instantly; the request is then sent in the background by the mutation outbox (`OutboxService`). On success the server's authoritative `PostView` / `CommentView` is mirrored back, reconciling the exact tallies.
- **Tapping your current vote removes it.** Vote intent is resolved against your existing vote: upvoting something you have already upvoted (or downvoting what you have already downvoted) clears your vote. There is no separate "remove vote" control — it is the same gesture again.
- **Coalescing.** Rapidly toggling back to your original state cancels the pending operation and reverts the optimistic projection, so a double-tap makes no net server call.
- **Rollback on permanent failure.** Transient failures (offline, rate-limit, 5xx) are retried with backoff; a permanent failure rolls the optimistic vote back to its pre-vote baseline and surfaces the error.
- **Offline vote toast.** When you vote (up, down, or remove a vote) from **post detail** while offline, a brief toast — "You're offline — we'll send your vote when you're back online." — confirms the vote is queued and will be sent automatically once connectivity returns. The vote still applies optimistically and is durably recorded by the outbox; the toast only sets expectations. Repeated offline votes coalesce into one toast (the existing toast's text and dismiss timer are reused rather than stacking).
- **Haptic on tap.** A vote fires a haptic at the moment of the tap (when the optimistic change is enqueued), not after the network round-trip.
- **State-aware presentation.** The active vote tints its glyph (per the accent/theme); a vote swipe slot reads Upvote, Downvote, or Remove vote according to current state. Comment subtitles show the score colored by your vote.
- **Signed-out votes are gated.** Tapping vote while signed out presents the "Sign in to vote" sheet (with a warning haptic) before anything is sent — the same [Sign-in gate](sign-in-gate.md) used by save / reply / report.

## Scenarios

### Upvote a post

- **Given** an open post
- **When** I tap upvote in the header action bar
- **Then** the score and highlighted upvote update immediately, and the vote is sent in the background
- **And** a haptic fires on the tap

### Remove a vote by tapping it again

- **Given** a post or comment I have already upvoted
- **When** I tap upvote again
- **Then** my vote is removed and the score returns accordingly

### Downvote switches an existing upvote

- **Given** a comment I have upvoted
- **When** I downvote it
- **Then** the upvote is immediately replaced by a downvote, and the server is reconciled in the background

### Vote on a comment from its menu

- **Given** a comment
- **When** I long-press it and choose Upvote or Downvote
- **Then** the vote is applied through the same optimistic outbox path

### A failed vote rolls back

- **Given** a vote that fails permanently on the server
- **When** I vote
- **Then** the optimistic change is rolled back to its previous state and the error is surfaced

### An offline vote is queued with a toast

- **Given** I am offline in post detail
- **When** I upvote, downvote, or remove a vote
- **Then** the vote applies immediately and a toast says "You're offline — we'll send your vote when you're back online."
- **And** the vote is queued and sent automatically when I'm back online
- **And** voting again while still offline updates the same toast rather than stacking another

### A signed-out vote is gated

- **Given** I am signed out
- **When** I tap vote
- **Then** a "Sign in to vote" sheet appears and nothing is sent

## Not supported / out of scope

- Batch voting and vote history are not provided.
- Configuring which swipe direction votes is part of [swipe-actions.md](swipe-actions.md), not this feature.
- The durable retry/rollback queue mechanics are shared with save / hide; see [Saving](saving.md) and the outbox.
