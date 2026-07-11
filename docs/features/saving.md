# Saving

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Post detail and comments](post-detail-and-comments.md), [Voting](voting.md), [Configurable swipe actions](swipe-actions.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Save a post or comment to come back to later, and unsave it the same way. Saved posts
collect in a dedicated **Saved** feed reachable from the account screen and the
subscriptions sidebar. Like voting, saving sends the change to the server and mirrors the
confirmed result back, so the bookmark state is authoritative.

## Behavior and rules

- **Save posts and comments.** A post is saved from its toolbar bookmark button or the header action-bar save button; a comment is saved from its context menu (Save / Unsave). Both kinds can also be saved via a configurable swipe slot — see [swipe-actions.md](swipe-actions.md).
- **Optimistic, durable save.** Saving (`setSaved(serverPostId:saved:)` / `setSaved(serverCommentId:saved:)`) writes the save state to the local database synchronously, before any network call, through the same durable mutation outbox used by voting — see [Voting](voting.md). The bookmark glyph and the saved indicator flip immediately; the outbox sends the change in the background with retry, rolling back to the pre-tap state on a permanent failure.
- **Toggle.** Save and unsave are the same affordance: the post toolbar button flips between an outline and a filled bookmark; the comment menu reads Save or Unsave depending on current state.
- **Haptic on action.** Toggling save fires a light haptic.
- **Offline save toast.** Saving or unsaving from **post detail** while offline shows a brief toast — "You're offline — we'll save this when you're back online." — confirming the change is queued and will be sent automatically once connectivity returns. The bookmark still flips optimistically and the action is durably recorded by the mutation outbox; the toast only sets expectations, and repeated offline saves coalesce into one toast rather than stacking.
- **Signed-out gate.** Saving requires being signed in. A signed-out account gets a "Sign in to save" alert and a warning haptic, and no call is made; the service layer also rejects a save from a signed-out account.
- **The Saved feed.** A Saved feed lists the signed-in account's **saved posts**. It is opened from the **Saved** button on the account screen and from the **Saved** row in the subscriptions sidebar (both shown only for signed-in accounts). Fetching the Saved feed is sign-in-gated and supports the same sort options and pagination as other feeds. When empty it shows "No saved posts yet / Posts you save will show up here."

## Scenarios

### Save a post from the toolbar

- **Given** an open post and a signed-in account
- **When** I tap the bookmark button
- **Then** the post is saved and the bookmark fills in once the server confirms
- **When** I tap it again
- **Then** the post is unsaved

### Save a comment from its menu

- **Given** a comment
- **When** I long-press it and choose Save
- **Then** the comment is saved (the menu now reads Unsave) and a saved indicator appears on it

### An offline save is queued with a toast

- **Given** I am offline in post detail
- **When** I save (or unsave) a post or comment
- **Then** the bookmark flips immediately and a toast says "You're offline — we'll save this when you're back online."
- **And** the change is queued and sent automatically when I'm back online

### Signed-out save is blocked

- **Given** a signed-out account
- **When** I try to save a post or comment
- **Then** a "Sign in to save" alert is shown with a warning haptic and nothing is saved

### Browse the Saved feed

- **Given** a signed-in account with saved posts
- **When** I open Saved from the account screen or the subscriptions sidebar
- **Then** I see a feed of my saved posts
- **And** an account with nothing saved sees a "No saved posts yet" empty state

## Not supported / out of scope

- The Saved feed lists **saved posts only** — saved comments are not collected into a list (a comment is saved, but is browsed in its own thread, not in the Saved feed).
- The Saved entry points are signed-in only; a signed-out account has no Saved feed.
- Optimistic UI: the save state is applied to the local DB synchronously at enqueue time (before any network call), so the bookmark flips immediately; a permanent server error rolls back to the pre-save state. Save is durable via the mutation outbox (the same OutboxService path as voting).
- Coalescing: tapping save then unsave before the request confirms collapses to a no-op (the pending operation is cancelled and the optimistic state reverts), with no net server call.
- No folders, tags, or organization of saved items.
- **Saved feed sort is server-side on Lemmy v3, a no-op on v4.** On a v3 instance the chosen sort is sent with the saved-posts fetch, so the Saved feed honours it like the frontpage/community feeds. On a v4 instance the saved-posts endpoint (`ListPersonSaved`) takes no sort parameter, so choosing a different sort re-fetches but the server returns its own default ordering. NSFW is not filtered server-side on the Saved feed either way — saved NSFW posts still appear (blurred when Blur NSFW is on), they are not hidden.
