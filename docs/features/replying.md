# Replying

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped — reply, edit, and delete/restore of your own comments are all optimistic and durable
- **Related:** [Post detail and comments](post-detail-and-comments.md), [Markdown editor](markdown-editor.md), [Voting](voting.md), [Draft persistence](draft-persistence.md), [Drafts and Outbox](drafts-and-outbox.md), [Locked posts](locked-posts.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Reply to a post or to any comment with a markdown composer presented as a sheet. The composer has Write and Preview modes; Post is enabled once there is non-whitespace content. Submitting immediately inserts an optimistic comment inline in the thread at its real position — dimmed with a "Sending..." status line — while the send runs in a durable background queue. On success the optimistic comment is replaced seamlessly by the real server comment. Replying requires being signed in.

You can also **edit** your own (non-deleted) comment: long-press it and choose Edit to reopen the composer prefilled with the current body. Saving updates the comment optimistically (the new body shows immediately, with an "Edited · Sending…" indicator) and durably enqueues the edit to the same content outbox the reply flow uses; on success the server's body replaces it, and a permanent failure parks the edit as failed (keeping your text) for retry. **Deleting / restoring** your own comment is a separate, idempotent toggle through the mutation outbox (documented in [Post detail and comments](post-detail-and-comments.md)).

## Behavior and rules

- **Reply to a post or a comment.** The post's toolbar reply button (and the post's swipe/menu reply where configured) starts a top-level comment; a comment's Reply action (context menu or swipe slot) starts a nested reply to that comment. The composer titles itself "Add comment" for a post reply and "Reply" for a comment reply.
- **Markdown composer sheet.** The composer is a medium/large sheet with a Write / Preview segmented control. On a regular-width iPad the sheet presents with medium/large detents and sits over the content at a comfortable width, rather than expanding to a full-screen modal. (The markdown editor and its toolbar are documented separately; this feature covers the reply flow.)
- **Post button gating.** Post is enabled only when the body has non-whitespace content and a submission is not already in flight.
- **Signed-out gate.** A signed-out account cannot reply: a "Sign in to comment" alert is shown instead of the composer, and the service rejects the create from a signed-out account.
- **Optimistic inline comment.** When you tap Post, the sheet dismisses immediately and the new comment appears at its real position in the thread (flush-left for a top-level reply; nested under its parent for a comment reply), dimmed with a "Sending..." status line. The send runs in the durable background queue; no manual refresh is needed to see your comment.
- **Durable background send with retry.** The send runs in a per-account background queue that retries transient failures with exponential backoff, auto-resumes when the network returns, and survives app relaunch. The optimistic comment remains visible and dimmed while retries are in progress.
- **Success: seamless replacement.** When the server confirms, the optimistic comment is replaced in place by the real comment from the server response with no visible flash or reorder.
- **Failure: tap-to-act.** A permanent failure (auth error, deleted parent, etc.) flips the optimistic comment from "Sending..." to a "Failed — tap to retry" state. Tapping offers:
  - **Retry** — requeues the item in the background queue.
  - **Edit** — reopens the composer seeded with the failed body text; posting again replaces the failed item.
  - **Discard** — removes the optimistic comment from the thread.
- **Durable draft per reply target.** The composer auto-saves the in-progress body to the durable draft store. Dismissing a non-empty composer without posting offers "Save Draft" / "Delete Draft" / "Cancel". Reopening the composer for the same target silently restores the text. See [Draft persistence](draft-persistence.md).
- **Permanent failures also surface a toast.** A non-blocking "Couldn't send comment — View" toast appears, linking to [Drafts and Outbox](drafts-and-outbox.md) where the failed item can be retried or discarded.
- **Replying is unavailable on a locked post.** When a post is locked, every reply affordance for it and its comments (post-detail "Add comment", a comment's swipe/long-press Reply, and the post's own swipe/long-press Reply wherever it's listed) is hidden rather than shown-disabled; if a reply is somehow initiated anyway, a "Comments are locked" message is shown instead of the composer as a backstop. Editing your own existing comment stays allowed on a locked post — only starting a *new* comment or reply is blocked. See [Locked posts](locked-posts.md).

### Editing your own comment

- **Edit action on your own non-deleted comment.** Long-pressing your own comment offers Edit (pencil) alongside Delete. A deleted comment offers Restore instead of Edit/Delete (editing a deleted comment isn't offered). The action opens the composer titled "Edit comment" with a "Save" button.
- **Prefilled with the current body.** The editor is seeded with the comment's current text. Save stays disabled until the body is both non-empty and changed from the original, so an unchanged edit can't be saved.
- **Optimistic in-place update.** Saving dismisses the sheet and immediately shows the new body on the existing comment row — keeping its votes, score, badges, and child replies — with an "Edited · Sending…" indicator. The edit runs through the durable content outbox (the performer calls the Lemmy edit-comment API); on success the server's reconciled body replaces the overlay with no flash or reorder.
- **Distinct from a reply draft.** An edit draft is keyed by the edited comment's id, so opening Edit never loads or clobbers a pending reply draft for the same post/parent (and vice versa).
- **Failure: tap-to-act.** A permanent failure flips the indicator to "Edit failed — tap to retry" while keeping the new body visible. Tapping offers Retry (re-enqueue the edit) or Discard Edit (drop the failed edit, reverting to the server body).
- **Dedup is skipped for edits.** Unlike a new reply, an edit targets an existing comment by design, so the lost-response duplicate-prevention check is skipped; the Lemmy edit API is idempotent, so a retried edit simply re-applies the same body.

## Scenarios

### Reply to a post

- **Given** an open post and a signed-in account
- **When** I tap the reply button, type a comment, and tap Post
- **Then** the sheet dismisses and my comment appears immediately in the thread, dimmed and marked "Sending..."
- **And** on success it becomes the real comment, no longer dimmed

### Reply to a comment

- **Given** a comment
- **When** I choose Reply, type a reply, and tap Post
- **Then** it appears nested under that comment immediately, then resolves to the real comment on success

### Preview before posting

- **Given** the composer with some markdown typed
- **When** I switch to Preview
- **Then** the rendered markdown is shown

### Empty content cannot be posted

- **Given** the composer with only whitespace
- **Then** the Post button is disabled

### Signed-out reply is blocked

- **Given** a signed-out account
- **When** I try to reply
- **Then** a "Sign in to comment" alert is shown and the composer is not presented

### A failed send shows tap-to-act options

- **Given** an optimistic comment that has permanently failed
- **When** I tap it
- **Then** I am offered Retry, Edit (reopen composer with the text), or Discard

### Saving a draft for later

- **Given** I typed a reply but tapped Cancel
- **When** I choose "Save Draft"
- **Then** reopening that composer (even after a relaunch) silently restores my text

### Edit your own comment

- **Given** my own non-deleted comment in an open post
- **When** I long-press it, choose Edit, change the body, and tap Save
- **Then** the sheet dismisses and the comment shows my new body immediately with an "Edited · Sending…" indicator
- **And** on success the indicator clears and the server's body is shown, with the comment's votes/score/badges/replies preserved

### An unchanged edit cannot be saved

- **Given** the edit composer prefilled with the comment's current body
- **When** I have not changed the text (or cleared it to whitespace)
- **Then** the Save button is disabled

### A failed edit shows tap-to-act options

- **Given** an edit that has permanently failed (still showing my new body)
- **When** I tap the comment
- **Then** I am offered Retry or Discard Edit (revert to the server body)

### Edit is not offered on a deleted comment

- **Given** my own comment that I have deleted
- **When** I long-press it
- **Then** I am offered Restore (not Edit or Delete)

## Not supported / out of scope

- **Replying on a locked post is not possible from within the app** — there is no client-side bypass; a moderator who wants to comment must first unlock the post via the moderation Lock/Unlock action (see [Locked posts](locked-posts.md)).
- **Editing your own post** uses the new-post composer (prefilled, with the community fixed), not this comment composer — durable + optimistic through the content outbox, documented in [Post detail and comments](post-detail-and-comments.md). ("Edit" in the failed-reply flow refers to editing an unsent failed item before resubmitting.)
- **Private messages** are sent through the same durable + optimistic content outbox (instant bubble, background retry, failure recovery), documented in [Private messages](private-messages.md) — not through this comment composer.
- **Dedup is not guaranteed.** If a send commits on the server but its response is lost before the app records success, and no later feed refresh imports the comment before an auto-retry, a duplicate comment may appear. This is a known rare edge case. Note: the duplicate-prevention check matches by post + author + body text only (it does not use the parent comment), so in the rare lost-response case a retried reply could incorrectly match a same-bodied comment elsewhere on the post.
- This feature covers replying only; creating a brand-new post is documented in [New post](new-post.md).
- The markdown editor internals (toolbar, live preview, image upload) are documented as their own feature, not here.
