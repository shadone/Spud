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
- **Confirm-then-mirror.** Saving calls the Lemmy API (`savePost` / `saveComment`) and then mirrors the server's returned view into the local database (`setSaved(serverPostId:saved:)` / `setSaved(serverCommentId:saved:)`). The bookmark glyph and the saved indicator update when the mirror lands.
- **Toggle.** Save and unsave are the same affordance: the post toolbar button flips between an outline and a filled bookmark; the comment menu reads Save or Unsave depending on current state.
- **Haptic on action.** Toggling save fires a light haptic.
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
- No optimistic UI: the bookmark updates after the server confirms.
- No folders, tags, or organization of saved items.
