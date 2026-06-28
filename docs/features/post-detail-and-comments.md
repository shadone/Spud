# Post detail and comments

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Voting](voting.md), [Saving](saving.md), [Replying](replying.md), [Sharing](sharing.md), [Configurable swipe actions](swipe-actions.md), [Marking posts read and hiding read posts](mark-read-and-hiding.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Opening a post shows its full content pinned at the top of the screen, with the
threaded comment tree scrolling below it. Comments nest with colored depth rails so a
thread stays scannable, and any comment can be collapsed — by tapping it or by a swipe —
to fold its replies away behind a "+N hidden" badge. A floating button jumps you to the
next top-level comment, and every comment and the post itself carry a context menu of
actions (vote, save, reply, share, report) plus moderator and admin actions when the
account has them.

## Behavior and rules

- **Pinned header + comment tree.** The post is the first row and stays at the top of the scroll; the comment tree follows it. The header renders the post title, body (markdown), the community-and-author attribution, a score / comment-count / age subtitle, and any media (image, video, or link preview), plus an inline action bar with **upvote, downvote, and save**.
- **Voting and saving update the header in place.** Tapping upvote / downvote / save optimistically updates the action bar and score without restarting the post's image load or rebuilding its body link-preview cards, so the header doesn't flicker or reflow on a vote. The media is only reloaded when it actually changes (e.g. a refresh fills in a thumbnail).
- **Attribution shows full handles.** The attribution reads "in `<Community>`@`<instance>` by `<Author>`@`<instance>`": the community's display name and the author's display name show their home instance host in a muted style (matching how instance hosts are dimmed in the post-list rows). Both `@instance` hosts are derived from the entity's own federation actor id (the author's home instance, e.g. `beehaw.org`), never from the local account's observing instance — so a post fetched on `lemmy.world` whose author lives on `beehaw.org` reads "by `<Author>`@beehaw.org", and the author handle deep-links to that home instance. The whole handle — display name plus `@instance` — is the tap target (to the community screen and the person profile respectively). A purely local handle still shows its own instance host.
- **Navigation bar actions.** The post's toolbar carries four buttons: open in Safari, reply to the post, share, and save (the save button shows a filled bookmark when the post is saved).
- **Threaded comments with depth rails.** A nested comment draws one colored rail per ancestor level on its leading edge, oldest ancestor first. Rail colors cycle through the active comment-ribbon theme so the same depth always reads as the same color; top-level comments draw no rail.
- **Inline body images.** Markdown images (`![alt](url)`) in the post body and in comment bodies render inline as part of the text flow, sized to the content width at the image's aspect ratio (capped in height so a tall image doesn't dominate). They load asynchronously and the row re-measures once the image arrives; a failed load shows a small broken-image tile. Tapping an inline image opens it in the fullscreen media viewer.
- **Tap to collapse.** Tapping a comment's body area collapses it (and expands it again); a light haptic fires. Tapping a link or inline image inside the author or body text follows the link (or opens the image) instead of collapsing. A collapsed comment hides its own body and all of its descendants, and shows a **"+N" badge** counting the hidden replies underneath it.
- **Collapse is a view-layer filter.** The full ordered comment tree is produced once from the database; collapse only hides rows from the visible list and is never written to the server or the database. Collapse state is dropped when a comment leaves the tree, and is not persisted across reopening the post.
- **Collapse via swipe too.** Collapse is also one of the assignable comment swipe slots, so gesture-first users can fold a thread without tapping. See [swipe-actions.md](swipe-actions.md) for the configurable swipe set.
- **"Load more replies" rows.** Where the server truncated a deep thread, a "N more replies" placeholder row appears. It is not collapsible and carries no per-comment actions.
- **Your just-posted comment appears immediately.** A comment you post shows up inline in the tree at its position right away in a dimmed "Sending…" state (and "Failed — tap to retry" if the send fails), before the server confirms it; on success it becomes a normal comment. The compose / draft / retry flow behind this is documented in [Replying](replying.md) and [Drafts & Outbox](drafts-and-outbox.md).
- **Jump to next top-level comment.** A floating chevron button at the bottom-trailing corner scrolls to the next top-level (depth-1) comment below the current position. It appears only while there is a next top-level comment to jump to and fades out otherwise.
- **Loading and empty placeholders sit below the post.** While comments load, a comment-shaped skeleton row shows directly under the post header; once the fetch settles with no comments, a centered "No comments yet — Be the first to comment." row takes its place. Both are in-flow rows that scroll with the content (right where the comments will appear), not a fixed background, so the pinned post header never covers them.
- **Pull to refresh.** Pulling down refetches the comment thread for the current sort.
- **Comment sort follows the default-sort preference.** The thread is sorted by the account's default comment sort (Hot, Top, New, Old, or Controversial). It is read once when the post opens; there is no in-screen control to change the sort for a single post.
- **Per-comment context menu.** Long-pressing a comment offers Upvote, Downvote, Reply, Save / Unsave, and Share. On other people's comments it then offers Report; on your own comment it instead offers **Edit** (pencil) and **Delete** (destructive, with a confirmation) — or just **Restore** when the comment is already deleted (editing a deleted comment isn't offered). Edit opens the composer prefilled with the comment's current body and updates it optimistically + durably through the content outbox (see [Replying](replying.md)). Delete / Restore flips the comment's deleted state instantly (optimistically) and is delivered durably through the idempotent mutation outbox — the same vote / save / hide pipeline that retries transient failures in the background and rolls the optimistic change back (with a "Couldn't update comment" toast) on a permanent failure. After the menu, a Moderation submenu appears when the account can moderate.
- **Per-post context menu.** Long-pressing the post header offers Share, then Report (only when it is not your own post), then the same Moderation submenu when applicable. The post is saved from the toolbar / header action bar, not from this menu.
- **Moderator and admin actions are capability-gated.** The account's moderation capability is fetched from the server when the screen appears (`fetchModerationCapability`). The Moderation submenu only appears when the account moderates this post's community, or is a site admin; otherwise it is absent. A signed-out account never sees it.
- **In-body link preview cards.** Links in post bodies and comment bodies render as a tappable preview card that always shows the link's anchor text (the `[label](url)` text from markdown). For YouTube, Invidious, and PeerTube video links, when the "Load Link Previews" setting is on, the card additionally shows a thumbnail with a play badge and the video title fetched via oEmbed; when the setting is off, the card shows only the anchor text and host. The post-header link card (for link-type posts) always shows the server-provided title and thumbnail regardless of this setting. Tapping any card opens the link through the external-link preference — see [External link handling](external-link-handling.md).
- **The post's vote / save / reply / report behaviors** are documented in their own features — see [Voting](voting.md), [Saving](saving.md), [Replying](replying.md), [Sharing](sharing.md).

## Scenarios

### The post stays pinned above its comments

- **Given** I open a post
- **Then** the post content shows at the top with an inline upvote / downvote / save bar
- **And** the comment tree scrolls below it

### A post with no comments shows the empty state below it

- **Given** I open a post that has no comments
- **Then** a "No comments yet — Be the first to comment." placeholder appears directly below the post content
- **And** it is not hidden behind the pinned post header

### Collapse a comment by tapping it

- **Given** a comment with replies
- **When** I tap the comment's body
- **Then** it collapses, hiding its replies, with a light haptic
- **And** it shows a "+N" badge counting the hidden replies
- **When** I tap it again
- **Then** it expands and the replies return

### Tapping a link does not collapse

- **Given** a comment whose text contains a link
- **When** I tap the link
- **Then** the link opens and the comment does not collapse

### Depth rails make nesting scannable

- **Given** a deeply nested reply
- **Then** it draws one colored rail per ancestor level on its leading edge
- **And** comments at the same depth share the same rail color

### Jump to the next top-level comment

- **Given** I am scrolled into a long thread with more top-level comments below
- **Then** a floating chevron button is visible
- **When** I tap it
- **Then** the list scrolls to the next top-level comment
- **And** the button hides once there is no further top-level comment below

### A comment's context menu

- **Given** another person's comment
- **When** I long-press it
- **Then** I get Upvote, Downvote, Reply, Save, Share, and Report
- **And** Report is omitted on my own comments

### Edit, delete, and restore my own comment

- **Given** my own non-deleted comment
- **When** I long-press it and choose Edit, change the body, and tap Save
- **Then** the new body shows on the comment instantly with an "Edited · Sending…" indicator (votes/score/badges/replies preserved), and the edit is enqueued to the content outbox; on success the server's body replaces the overlay (see [Replying](replying.md))
- **And** choosing Delete (and confirming) instead flips the comment to deleted instantly via the mutation outbox; if it already shows deleted, the menu offers Restore (no confirmation, and no Edit), which flips it back. A permanent server failure rolls a delete/restore back and shows a "Couldn't update comment" toast.

### Moderation actions appear only with capability

- **Given** I moderate the post's community
- **When** I long-press a comment or the post
- **Then** a Moderation submenu is offered (Remove / Restore, and comment Distinguish or post Lock / Feature)
- **And** an account that does not moderate the community sees no Moderation submenu

### Pull to refresh the thread

- **Given** an open post
- **When** I pull down
- **Then** the comment thread refetches for the current sort

### Link preview cards in post and comment bodies

- **Given** a post or comment body that contains a markdown link
- **Then** a tappable preview card renders at the link's position, showing the anchor text
- **And** when "Load Link Previews" is on and the link is a YouTube, Invidious, or PeerTube video, the card additionally shows a thumbnail with a play badge and the video title
- **And** when "Load Link Previews" is off, the card shows only the anchor text and host — no third-party fetch is made
- **When** I tap the card
- **Then** the link opens through the external-link preference

### Post-header link card shows server-provided title and thumbnail

- **Given** a link-type post
- **When** I open its detail screen
- **Then** the header shows a link preview card with the server-provided title and thumbnail

### Voting does not flicker the post media

- **Given** I am viewing a post with an image or body link-preview cards
- **When** I upvote, downvote, or save it
- **Then** the action bar and score update in place
- **And** the post image and link-preview cards stay put — no flicker, reload, or reflow

## Not supported / out of scope

- **No in-screen comment-sort control.** The thread uses the account's default comment sort; there is no per-post picker to re-sort it without changing the global default. (Setting the default lives in Settings.)
- **No edit or delete of your own *post*** from this screen — see [Replying](replying.md). (Editing, deleting, and restoring your own *comment* ARE supported via its context menu — see above.)
- Collapse state is not persisted: reopening the post starts fully expanded.
- "Load more replies" placeholders are not collapsible and have no per-comment actions.
- The post is saved from the toolbar or header action bar (or a swipe), not from the post's context menu.
- Swipe-gesture configuration itself is a separate feature — see [swipe-actions.md](swipe-actions.md).
