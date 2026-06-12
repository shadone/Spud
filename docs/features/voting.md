# Voting

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Post detail and comments](post-detail-and-comments.md), [Saving](saving.md), [Configurable swipe actions](swipe-actions.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Upvote or downvote any post or comment. A vote is applied by sending it to the server and
mirroring the server's confirmed result back into the app, so the score and your vote
state you see are what the server recorded. Tapping the same direction you already voted
removes your vote. Votes are reachable from the post's action bar, comment swipe slots,
and the per-comment context menu.

## Behavior and rules

- **Posts and comments both vote.** The post header has inline upvote / downvote buttons; comments expose Upvote and Downvote through their context menu and through their swipe slots.
- **Confirm-then-mirror.** A vote calls the Lemmy API first (`likePost` / `likeComment`); only the server's returned view is written back into the local database (`vote(serverPostId:vote:)` / `vote(serverCommentId:vote:)`). There is no optimistic local change before the server confirms — the displayed score and highlight update when the mirror lands.
- **Tapping your current vote removes it.** Vote intent is resolved against your existing vote: upvoting something you have already upvoted (or downvoting what you have already downvoted) sends a neutral/“remove” to the server, clearing your vote. There is no separate "remove vote" control — it is the same gesture again.
- **Haptic on submit.** Submitting a vote fires a success haptic.
- **State-aware presentation.** The active vote tints its glyph (upvote red / downvote per theme); a vote swipe slot reads Upvote, Downvote, or Remove vote according to current state. Comment subtitles show the score colored by your vote.
- **Failures surface an alert.** If the vote call fails, an error alert is shown; the local state is unchanged because nothing was mirrored.
- **No client-side signed-out gate on voting.** Unlike save / reply / report, a vote is not pre-empted for a signed-out account: the call is attempted and, when it fails server-side, an error alert is shown. (Save and reply, by contrast, present a "Sign in to…" alert before attempting.)

## Scenarios

### Upvote a post

- **Given** an open post
- **When** I tap upvote in the header action bar
- **Then** the vote is sent to the server, and on confirmation the score and the highlighted upvote reflect it
- **And** a success haptic fires on submit

### Remove a vote by tapping it again

- **Given** a post or comment I have already upvoted
- **When** I tap upvote again
- **Then** my vote is removed and the score returns accordingly

### Downvote switches an existing upvote

- **Given** a comment I have upvoted
- **When** I downvote it
- **Then** the upvote is replaced by a downvote once the server confirms

### Vote on a comment from its menu

- **Given** a comment
- **When** I long-press it and choose Upvote or Downvote
- **Then** the vote is applied through the same confirm-then-mirror path

### A failed vote shows an alert

- **Given** the vote call fails (for example, a signed-out account or a network error)
- **When** I vote
- **Then** an error alert is shown and my vote state is unchanged

## Not supported / out of scope

- No optimistic UI: the score and vote highlight update only after the server confirms.
- No pre-emptive "sign in to vote" gate — a signed-out vote is attempted and surfaces an error if it fails. (This differs from save and reply, which gate before attempting.)
- Voting on a per-post comment-sort basis, batch voting, or vote history are not provided.
- Configuring which swipe direction votes is part of [swipe-actions.md](swipe-actions.md), not this feature.
