# Removed and unavailable posts

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Post detail and comments](post-detail-and-comments.md), [Moderator / admin actions](moderation-actions.md), [Voting](voting.md), [Saving](saving.md), [Empty, error, and loading states](empty-error-loading-states.md)

## What it does

When a post disappears from the server — because a moderator removed it, the author deleted it, or the post's origin instance de-federated — Spud surfaces a clear, honest placeholder rather than an infinite loading spinner or a generic error. A neutral gray badge on the feed cell signals that the app's cached copy can no longer be confirmed as live. If the post later reappears (a moderator restores it, re-federation happens), the next successful fetch clears the flag and the post renders normally again. Moderators and the post's own author retain full access to the content so that privileged actions (Restore, editorial review) are still possible.

## Behavior and rules

- **Detection at every server touchpoint.** Spud marks a post "unavailable" when the server returns a `couldnt_find_post` error on any of: opening the post detail (the comment fetch), pull-to-refresh (`getPost`), or any outbox mutation (vote, save, hide). The flag is persisted immediately and survives app relaunch.
- **Three server-side states.** The app distinguishes:
  - **Ambiguous unavailability** (`couldnt_find_post` with no further detail): title "This post is no longer available", message "It may have been removed."
  - **Server-confirmed removal** (the post view carries `removed: true`, non-moderator viewer): "Removed by moderator."
  - **Server-confirmed deletion** (the post view carries `deleted: true`, viewer is not the author and not a moderator): "Deleted by author."
- **Visibility gating for privileged viewers.** Moderators of the post's community and the post's own author still see the full post content even when the post is removed or deleted, because they may need to act on or review it. The placeholder is shown only to unprivileged viewers.
- **Post detail replaced with a placeholder.** When an unprivileged viewer opens a post that the app has flagged unavailable, the post-detail screen shows a centered placeholder (symbol, title, message) instead of the post content and comment tree. The copy varies by cause as described above.
- **Neutral feed badge for ambiguous unavailability.** A gray `exclamationmark.octagon` badge marks a feed cell whose post has been flagged with `couldnt_find_post`. This badge is deliberately neutral — Spud does not know the reason in this case. It is distinct from the red "Removed" and "Deleted" badges that appear when the server has confirmed the reason.
- **Interaction toast on unavailable post.** Voting, saving, or hiding a post that is no longer found on the server surfaces a specific "This post is no longer available" toast instead of the generic error, and the neutral feed badge appears on the cell.
- **Deep-link routing resolves cleanly.** Following a deep link to a post that the server no longer serves shows the placeholder immediately rather than an indefinite loading spinner. This also covers the pre-existing hang that occurred when the comment fetch returned `couldnt_find_post` before the detail was fully loaded.
- **Automatic recovery.** If the server serves the post successfully on a later fetch (e.g. a moderator restores it, re-federation succeeds), the unavailable flag is cleared and the post renders as normal. No manual intervention is required.

## Scenarios

### Opening a cached post that the server can no longer serve

- **Given** I have a cached post in my feed whose origin server returns `couldnt_find_post` when its detail is fetched (e.g. it was removed or de-federated)
- **When** I open the post
- **Then** the post-detail screen is replaced with a centered placeholder
- **And** the title reads "This post is no longer available" and the message reads "It may have been removed."
- **And** the post's feed cell gains a neutral gray `exclamationmark.octagon` badge

### Opening a server-confirmed removed post (non-moderator)

- **Given** I am not a moderator of the post's community
- **And** the server's post view carries `removed: true`
- **When** I open the post
- **Then** the placeholder shows "Removed by moderator" instead of the post content

### Opening a server-confirmed deleted post (non-author, non-moderator)

- **Given** I am not the post's author and not a moderator
- **And** the server's post view carries `deleted: true`
- **When** I open the post
- **Then** the placeholder shows "Deleted by author" instead of the post content

### Voting on an unavailable post from the feed

- **Given** a feed cell for a post that is no longer on the server
- **When** I attempt to vote (upvote or downvote) on it
- **Then** a toast reads "This post is no longer available" (not the generic error message)
- **And** the feed cell gains the neutral gray badge

### Opening a post via a deep link that is no longer available

- **Given** I follow a deep link (from a notification, share sheet, or Safari extension) to a post that the server returns `couldnt_find_post` for
- **When** the post detail opens
- **Then** the placeholder is shown immediately rather than an indefinite loading spinner

### Moderator opens a removed post

- **Given** I moderate the post's community
- **And** the post has been removed (server-confirmed or locally flagged)
- **When** I open the post
- **Then** the full post content and comment tree are shown (the placeholder is not shown)
- **And** the Moderation context menu includes the Restore action

### Author opens their own deleted post

- **Given** I am the post's author
- **And** the post has been deleted
- **When** I open the post
- **Then** the full post content is shown (the placeholder is not shown)
- **And** the post's own-author context menu includes the Restore action

### A restored post recovers automatically

- **Given** a post that is flagged as unavailable in the feed
- **When** the server successfully returns the post on the next fetch (e.g. after a moderator restores it)
- **Then** the unavailable flag is cleared
- **And** the feed cell no longer shows the neutral badge
- **And** opening the post shows the content normally

## Not supported / out of scope

- Distinguishing removal from de-federation for ambiguous `couldnt_find_post` responses — both show the same "no longer available" copy.
- Hiding or removing the post from the feed automatically — unavailable posts stay in the feed with the neutral badge rather than being dropped.
- A live auto-recovery while the post-detail screen is open: if a post is restored while the placeholder screen is visible, the user must pop back and re-open the post to see the restored content.
- A per-post modlog browser showing the removal reason — the placeholder copy is fixed based on the server state, not a fetched reason string.
- Detecting `couldnt_find_post` returned by `getComments` alone (some server versions may return an empty comment tree instead of an error for removed posts); in that case the post reveals as gone only on the next `getPost` or vote.
