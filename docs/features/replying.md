# Replying

- **Surfaces:** `iphone`, `ipad`
- **Status:** partial — editing and deleting your own comment are not supported
- **Related:** [Post detail and comments](post-detail-and-comments.md), [Markdown editor](markdown-editor.md), [Voting](voting.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Reply to a post or to any comment with a markdown composer presented as a sheet. The
composer has Write and Preview modes; Post is enabled once there is non-whitespace
content. Submitting sends the comment to the server and the thread refreshes the new
comment in. Replying requires being signed in.

## Behavior and rules

- **Reply to a post or a comment.** The post's toolbar reply button (and the post's swipe/menu reply where configured) starts a top-level comment; a comment's Reply action (context menu or swipe slot) starts a nested reply to that comment. The composer titles itself "Add comment" for a post reply and "Reply" for a comment reply.
- **Markdown composer sheet.** The composer is a medium/large sheet with a Write / Preview segmented control. (The markdown editor and its toolbar are documented separately as the composer/markdown editor feature; this feature covers the reply flow.)
- **Post button gating.** Post is enabled only when the body has non-whitespace content and a submission is not already in flight.
- **Signed-out gate.** A signed-out account cannot reply: a "Sign in to comment" alert is shown instead of the composer, and the service rejects the create from a signed-out account.
- **Submit then refresh.** Posting calls the Lemmy API (`createComment`) with the post id and, for a comment reply, the parent comment id; on success the sheet dismisses and the thread's observation brings the new comment in. There is no manual insertion of an optimistic comment.
- **Failure keeps your draft.** If submission fails, an error alert is shown and the composer stays open with the text intact so you can retry; the Post button returns.

## Scenarios

### Reply to a post

- **Given** an open post and a signed-in account
- **When** I tap the reply button and type a comment, then tap Post
- **Then** the comment is sent and the sheet dismisses
- **And** the new comment appears in the thread

### Reply to a comment

- **Given** a comment
- **When** I choose Reply, type a reply, and Post
- **Then** it is added as a nested reply under that comment

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

### A failed submission keeps the draft

- **Given** a reply that fails to send
- **When** the failure occurs
- **Then** an error alert is shown and the composer stays open with my text

## Not supported / out of scope

- **Editing your own comment is not supported.** There is no edit action in any menu and no edit path in the data layer.
- **Deleting your own comment is not supported.** There is no delete action for your own comment or post. (Moderator removal is a separate, capability-gated action — see [post-detail-and-comments.md](post-detail-and-comments.md).)
- This feature covers replying only; creating a brand-new post is a separate content-creation feature.
- The markdown editor internals (toolbar, live preview, image upload) are documented as their own feature, not here.
