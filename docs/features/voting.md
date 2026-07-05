# Voting

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Post detail and comments](post-detail-and-comments.md), [Saving](saving.md), [Sign-in gate on write actions](sign-in-gate.md), [Configurable swipe actions](swipe-actions.md), [Accessibility](accessibility.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

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
- **State-aware presentation.** The active vote is shown as a structural cue — a filled capsule or a dog-ear fold — rather than only a hue change. See "Voted-state presentation" below for full details. A vote swipe slot reads Upvote, Downvote, or Remove vote according to current state. Comment subtitles show the score colored by your vote.
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

## Voted-state presentation

The voted state is a **structural cue** — a real weight change that reads at a glance and in monochrome — not just a hue change. The cue adapts to whether vote buttons are visible:

- **Vote pill (buttons shown).** When the trailing vote arrows are visible (the default, `Show Vote Buttons` preference on), the chosen arrow becomes a **solid filled capsule**: the vote-color token as the background fill, a white glyph on top. The other arrow stays a tertiary hairline outline. On selection the fill springs in with a scale animation (0.9 → 1.0) and the opposite arrow dims; on removal the fill scales back out.
- **Dog-ear fold (buttons hidden).** When `Show Vote Buttons` is off (gesture-voting mode), there is no arrow control to restyle. Instead a **folded corner** in the trailing edge of the post cell carries the state: an upvote folds from the **top** corner; a downvote folds from the **bottom** corner. Each fold shows a small debossed white arrow so orientation encodes direction before color does. The fold is decorative (not a tap target) and does not stack with the pill — exactly one cue is shown per cell, gated by the same preference.
- **Post-detail header button.** The header's upvote or downvote button goes **solid** (filled capsule, white glyph on the vote-color token) when active, matching the list-cell pill style.
- **Comment score mini-pill.** Each comment's inline score becomes a **filled mini-pill** (white arrow + white number on the token) when you have voted on that comment. A neutral comment still shows its score as a hairline arrow and number in secondary color with no fill, so the score is never hidden. The pill scales with Dynamic Type and coexists cleanly with the fresh-comment wash, distinguished/OP, saved bookmark, "NEW" pill, and depth rails.

### Vote colors

- **Upvote** = the user's accent color (default Lemmy teal). Accent-aware; unchanged from before.
- **Downvote** = indigo (#5b57e0). Changed app-wide from the previous periwinkle — this is the single `downColor` token, so every downvote surface (score arrows, swipe actions, post-list capsule, post-detail header, comment mini-pill) is now indigo.
- Filled capsule and mini-pill glyphs and numbers are always **white** for contrast on both tokens.
- The neutral / inactive arrow stays `.tertiaryLabel` (unchanged).

### Motion and accessibility

- **Spring animation.** The fill springs in on commit (scale 0.9 → 1.0, ~180 ms); the opposite arrow dims. Springs back out on removal.
- **Reduce Motion.** Cross-fades the fill instead of scaling. Gated on the system Reduce Motion setting; no peel or spring plays.
- **VoiceOver.** Fill weight and arrow shape carry the state structurally; color is reinforcement only. The active vote control gains the `.selected` trait so VoiceOver announces the current state. The dog-ear fold is marked decorative (`isAccessibilityElement = false`).
- **Dynamic Type.** The capsule and mini-pill grow with the glyph metrics at the current text size. The fold is fixed geometry.
- **No new user setting.** The pill-vs-fold choice is driven entirely by the existing `Show Vote Buttons` preference; the two cues never stack.

## Voted-state scenarios

### Scanning the feed — an upvoted post shows a filled up-capsule

- **Given** the feed with vote buttons visible (the default)
- **When** I scroll past a post I have upvoted
- **Then** the upvote arrow shows as a solid filled capsule with a white glyph on the accent color
- **And** the downvote arrow stays a hairline outline

### Scanning the feed — a downvoted post shows a filled indigo capsule

- **Given** the feed with vote buttons visible
- **When** I scroll past a post I have downvoted
- **Then** the downvote arrow shows as a solid filled capsule with a white glyph on an indigo background

### Vote buttons hidden — an upvoted post shows a top-corner fold

- **Given** I have turned off Show Vote Buttons
- **When** I scroll past a post I have upvoted
- **Then** a folded corner appears at the **top** trailing edge of the cell, with a small debossed arrow
- **And** no vote arrow controls or filled capsule are shown

### Vote buttons hidden — a downvoted post shows a bottom-corner fold

- **Given** I have turned off Show Vote Buttons
- **When** I scroll past a post I have downvoted
- **Then** a folded corner appears at the **bottom** trailing edge of the cell
- **And** no vote arrow controls or filled capsule are shown

### Post detail — active vote button shows as a filled capsule

- **Given** I have upvoted a post and open its detail screen
- **Then** the upvote button in the action bar shows as a filled capsule (white arrow on accent color)
- **And** the downvote button stays a hairline outline

### A voted comment shows a filled score mini-pill

- **Given** a comment I have downvoted
- **Then** the comment's score shows as a filled mini-pill with a white arrow and white number on an indigo background

### A neutral comment still shows its score

- **Given** a comment I have not voted on
- **Then** the comment's score shows as a hairline arrow and number in secondary color with no fill

### Reduce Motion — voting fills without spring

- **Given** Reduce Motion is enabled
- **When** I upvote a post
- **Then** the filled capsule appears via a cross-fade, not a scale spring

## Not supported / out of scope

- Batch voting and vote history are not provided.
- Configuring which swipe direction votes is part of [swipe-actions.md](swipe-actions.md), not this feature.
- The durable retry/rollback queue mechanics are shared with save / hide; see [Saving](saving.md) and the outbox.
