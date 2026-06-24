# Replying

- **Surfaces:** `iphone`, `ipad`
- **Status:** partial — editing and deleting your own comment are not supported
- **Related:** [Post detail and comments](post-detail-and-comments.md), [Markdown editor](markdown-editor.md), [Voting](voting.md), [Draft persistence](draft-persistence.md), [Drafts and Outbox](drafts-and-outbox.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Reply to a post or to any comment with a markdown composer presented as a sheet. The composer has Write and Preview modes; Post is enabled once there is non-whitespace content. Submitting immediately inserts an optimistic comment inline in the thread at its real position — dimmed with a "Sending..." status line — while the send runs in a durable background queue. On success the optimistic comment is replaced seamlessly by the real server comment. Replying requires being signed in.

## Behavior and rules

- **Reply to a post or a comment.** The post's toolbar reply button (and the post's swipe/menu reply where configured) starts a top-level comment; a comment's Reply action (context menu or swipe slot) starts a nested reply to that comment. The composer titles itself "Add comment" for a post reply and "Reply" for a comment reply.
- **Markdown composer sheet.** The composer is a medium/large sheet with a Write / Preview segmented control. (The markdown editor and its toolbar are documented separately; this feature covers the reply flow.)
- **Post button gating.** Post is enabled only when the body has non-whitespace content and a submission is not already in flight.
- **Signed-out gate.** A signed-out account cannot reply: a "Sign in to comment" alert is shown instead of the composer, and the service rejects the create from a signed-out account.
- **Optimistic inline comment.** When you tap Post, the sheet dismisses immediately and the new comment appears at its real position in the thread (flush-left for a top-level reply; nested under its parent for a comment reply), dimmed with a "Sending..." status line. The send runs in the durable background queue; no manual refresh is needed to see your comment.
- **Durable background send with retry.** The send runs in a per-account background queue that retries transient failures with exponential backoff, auto-resumes when the network returns, and survives app relaunch. The optimistic comment remains visible and dimmed while retries are in progress.
- **Success: seamless replacement.** When the server confirms, the optimistic comment is replaced in place by the real comment from the server response with no visible flash or reorder.
- **Failure: tap-to-act.** A permanent failure (auth error, deleted parent, etc.) flips the optimistic comment from "Sending..." to a "Failed — tap to retry" state. Tapping offers:
  - **Retry** — requeues the item in the background queue.
  - **Edit** — reopens the composer seeded with the failed body text; posting again replaces the failed item.
  - **Discard** — removes the optimistic comment from the thread.
- **Durable draft per reply target.** The composer auto-saves the in-progress body to the durable draft store. Dismissing a non-empty composer without posting offers "Save Draft" / "Delete Draft" / "Keep Editing". Reopening the composer for the same target silently restores the text. See [Draft persistence](draft-persistence.md).
- **Permanent failures also surface a toast.** A non-blocking "Couldn't send comment — View" toast appears, linking to [Drafts and Outbox](drafts-and-outbox.md) where the failed item can be retried or discarded.

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

## Not supported / out of scope

- **Editing your own comment is not supported.** There is no edit action on a successfully posted comment. ("Edit" in the failed-item flow refers to editing an unsent failed item before resubmitting, not editing a comment that is already on the server.)
- **Deleting your own comment is not supported.** There is no delete action for your own comment or post. (Moderator removal is a separate, capability-gated action — see [post-detail-and-comments.md](post-detail-and-comments.md).)
- **Private messages.** The DM composer still uses the old blocking flow; durable/optimistic behavior for private messages is not yet supported.
- **Dedup is not guaranteed.** If a send commits on the server but its response is lost before the app records success, and no later feed refresh imports the comment before an auto-retry, a duplicate comment may appear. This is a known rare edge case.
- This feature covers replying only; creating a brand-new post is documented in [New post](new-post.md).
- The markdown editor internals (toolbar, live preview, image upload) are documented as their own feature, not here.
