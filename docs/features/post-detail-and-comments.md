# Post detail and comments

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped — inline "load more replies" expansion pending release (implemented + tested on `feat/load-more-replies`; not yet merged, and the LemmyKit pin it needs hasn't been tagged a release)
- **Related:** [Voting](voting.md), [Saving](saving.md), [Replying](replying.md), [Sharing](sharing.md), [Configurable swipe actions](swipe-actions.md), [Marking posts read and hiding read posts](mark-read-and-hiding.md), [Feed loading and pagination](feed-loading.md), [Media viewer and inline video](media-viewer.md), [Reminders](reminders.md), [Locked posts](locked-posts.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Opening a post shows its full content pinned at the top of the screen, with the
threaded comment tree scrolling below it. Comments nest with colored depth rails so a
thread stays scannable, and any comment can be collapsed — by tapping it or by a swipe —
to fold its replies away behind a "+N hidden" badge. A floating button jumps you to the
next top-level comment, and every comment and the post itself carry a context menu of
actions (vote, save, reply, share, remind me, report) plus moderator and admin actions
when the account has them.

## Behavior and rules

- **Pinned header + comment tree.** The post is the first row and stays at the top of the scroll; the comment tree follows it. The header renders the post title, body (markdown), the community-and-author attribution, a score / comment-count / age subtitle, and any media (image, video, or link preview), plus an inline action bar with **upvote, downvote, and save**.
- **Voting and saving update the header in place.** Tapping upvote / downvote / save optimistically updates the action bar and score without restarting the post's image load or rebuilding its body link-preview cards, so the header doesn't flicker or reflow on a vote. The media is only reloaded when it actually changes (e.g. a refresh fills in a thumbnail).
- **Attribution shows full handles.** The attribution reads "in `<Community>`@`<instance>` by `<Author>`@`<instance>`": the community's display name and the author's display name show their home instance host in a muted style (matching how instance hosts are dimmed in the post-list rows). Both `@instance` hosts are derived from the entity's own federation actor id (the author's home instance, e.g. `beehaw.org`), never from the local account's observing instance — so a post fetched on `lemmy.world` whose author lives on `beehaw.org` reads "by `<Author>`@beehaw.org", and the author handle deep-links to that home instance. The whole handle — display name plus `@instance` — is the tap target (to the community screen and the person profile respectively). A purely local handle still shows its own instance host.
- **Navigation bar actions.** The post's toolbar carries four buttons: open in Safari, reply to the post, share, and save (the save button shows a filled bookmark when the post is saved).
- **Threaded comments with depth rails.** A nested comment draws one colored rail per ancestor level on its leading edge, oldest ancestor first. Rail colors cycle through the active comment-ribbon theme so the same depth always reads as the same color; top-level comments draw no rail.
- **Header image: cached thumbnail first, then full resolution.** For an image post, the header paints the feed cell's already-cached thumbnail immediately while the full-resolution image loads behind it (the same instant-first-frame idea as the media viewer), so opening a post from the feed never shows an empty gray box first. The full image replaces the thumbnail in place when it arrives.
- **"Low-res preview" pill when the full image can't load.** If the full-resolution image *fails* to load but a thumbnail is already on screen (e.g. offline, after browsing it in the feed), the header keeps the thumbnail and shows a small tappable **"Low-res preview"** pill over it instead of a hard failure plate — so you still see *something* and know it's degraded. Tapping the pill retries the full image; long-pressing it offers **Open in browser**. The hard failure plate ("Image couldn't load", with **Retry** and **Open in browser**) only appears when nothing is on screen at all (no thumbnail to fall back to). (VoiceOver: the pill is a button labelled "Low-res preview" with a hint that the full image is unavailable.)
- **Inline body images.** Markdown images (`![alt](url)`) in the post body and in comment bodies render inline as part of the text flow, sized to the content width at the image's aspect ratio (capped in height so a tall image doesn't dominate). They load asynchronously, and once the image arrives the row snaps to its new height instantly, with no animation — an animated re-measure would zoom the never-before-laid-out image in from a corner, so growth is never eased or sprung. A failed load shows a small broken-image tile with **Retry** and **Open in browser** — Retry re-attempts the load in place, so a transient failure doesn't strand the image as broken until you leave the screen. Tapping a loaded inline image opens it in the fullscreen media viewer.
- **Tap to collapse.** Tapping a comment's body area collapses it (and expands it again); a light haptic fires. Tapping a link or inline image inside the author or body text follows the link (or opens the image) instead of collapsing. A collapsed comment hides its own body and all of its descendants, and shows a **"+N" badge** counting the hidden replies underneath it. Collapsing (like voting) refreshes the header and every visible comment in place, flash-free: inline body images and link-preview cards whose content is unchanged are not reloaded, so neighboring rows never flicker.
- **Collapse is a view-layer filter.** The full ordered comment tree is produced once from the database; collapse only hides rows from the visible list and is never written to the server or the database. Collapse state is dropped when a comment leaves the tree, and is not persisted across reopening the post.
- **Collapse via swipe too.** Collapse is also one of the assignable comment swipe slots, so gesture-first users can fold a thread without tapping. See [swipe-actions.md](swipe-actions.md) for the configurable swipe set.
- **Opening a post loads the whole comment tree down to a depth cutoff.** The initial fetch asks the server for the post's comment tree traversed eight levels deep, so a busy post arrives complete rather than as a partial slice — the comment count in the header and the tree beneath it agree. Replies deeper than the cutoff are not loaded up front; each comment that still has unloaded replies gets a "N more replies" row (below), so depth is reached on demand instead of on open.
- **"Load more replies" rows are tappable and expand inline.** Where a comment reports more replies than the loaded tree carries, a "N more replies" row (singular "1 more reply" for exactly one) appears beneath it. Tapping it swaps the row's text for a spinner while the missing subtree fetches, then splices the replies in at their correct depth right where the row was — the rest of the tree isn't reloaded, and a second tap while it's loading is ignored (no duplicate fetch). If that subtree is itself deep enough to contain replies beyond a single fetch, a fresh "N more replies" row appears further down under whichever descendant still has missing children, tappable the same way — so a very deep thread self-heals by expanding one layer at a time rather than leaving a stale or broken row. If the fetch fails (offline, server error), the row reverts from its spinner back to the "N more replies" count and a "Couldn't load more replies" toast appears; tapping the row again retries. This works the same talking to a v3 or a native v4 Lemmy server. The row is never collapsible and carries no swipe or long-press actions — tapping it is its only interaction.
- **Your just-posted comment appears immediately.** A comment you post shows up inline in the tree at its position right away in a dimmed "Sending…" state (and "Failed — tap to retry" if the send fails), before the server confirms it; on success it becomes a normal comment. The compose / draft / retry flow behind this is documented in [Replying](replying.md) and [Drafts & Outbox](drafts-and-outbox.md).
- **Jump to next top-level comment.** A floating chevron button at the bottom-trailing corner scrolls to the next top-level (depth-1) comment below the current position. It appears only while there is a next top-level comment to jump to and fades out otherwise.
- **Comment permalink anchoring.** Opening the post via a `/comment/<id>` permalink (a deep link or the "Open in Spud" share extension) scrolls to that comment once the tree loads — expanding any collapsed ancestors — and flashes it with a one-time tint (skipped under Reduce Motion, where the scroll-to-top is the cue). If the target comment isn't in the post's loaded tree, it lands on the post without scrolling. See [Open in Spud](share-extension.md).
- **Loading, empty, and failed placeholders sit below the post.** While comments load, a comment-shaped skeleton row shows directly under the post header; once the fetch *succeeds* with no comments, a "No comments yet / Be the first to comment." row takes its place. All of these are in-flow rows that scroll with the content (right where the comments will appear), not a fixed background, so the pinned post header never covers them.
- **A failed comment load shows a truthful offline state, not the empty state.** When the comment fetch *fails* and there are no comments to show, the comments region shows a designed inline failure row — classified **offline** ("You're offline" / "Spud will retry automatically when you're back online."), **unreachable** ("Couldn't reach the server" / "The server may be down or your connection is unstable."), or **malformed** ("Something went wrong") — with a **Try again** button, instead of the misleading "No comments yet" empty state. The genuine empty state shows *only* after a fetch succeeds with zero comments; the failed state takes precedence whenever the last load errored with nothing on screen. The copy and classification mirror the feed's first-load error states — see [Feed loading and pagination](feed-loading.md). Tapping **Try again** re-fetches the thread, and — like the feed — an **offline** failure also re-fetches automatically the moment connectivity returns (so the "Spud will retry automatically when you're back online" promise is true, not just a manual Retry). (A pull-to-refresh failure when comments are *already* on screen keeps the list and surfaces a toast instead — it never drops into this failed state.)
- **Pull to refresh.** Pulling down refetches the comment thread for the current sort.
- **Comment sort follows the default-sort preference.** The thread is sorted by the account's default comment sort (Hot, Top, New, Old, or Controversial). It is read once when the post opens; there is no in-screen control to change the sort for a single post.
- **Per-comment context menu.** Long-pressing a comment offers Upvote, Downvote, Reply, Save / Unsave, Share, and a "Remind Me…" submenu scoped to that comment's thread (omitted if the comment isn't fully loaded — e.g. a "load more" placeholder; see [Reminders](reminders.md)). On other people's comments it then offers Report; on your own comment it instead offers **Edit** (pencil) and **Delete** (destructive, with a confirmation) — or just **Restore** when the comment is already deleted (editing a deleted comment isn't offered). Edit opens the composer prefilled with the comment's current body and updates it optimistically + durably through the content outbox (see [Replying](replying.md)). Delete / Restore flips the comment's deleted state instantly (optimistically) and is delivered durably through the idempotent mutation outbox — the same vote / save / hide pipeline that retries transient failures in the background and rolls the optimistic change back (with a "Couldn't update comment" toast) on a permanent failure. After the menu, a Moderation submenu appears when the account can moderate.
- **Per-post context menu.** Long-pressing the post header offers Share, then Report (only when it is not your own post), then — on your own post — **Edit** (pencil), **Delete** (destructive, with a confirmation), or **Restore** when it's already deleted, then the same Moderation submenu when applicable. The post is saved from the toolbar / header action bar, not from this menu.
- **Edit / delete / restore your own post.** The post overflow ("•••") menu and the header long-press offer these on your own post. **Edit** opens the new-post composer prefilled with the post's current title / body / URL / NSFW (the community is fixed, not changeable); saving updates the post optimistically (the header reflects the change immediately) and durably through the content outbox (`editPost`) — on success the server's version reconciles, and a permanent failure parks the edit as failed (keeping your text) for retry, just like a comment edit. **Delete / Restore** flips the post's deleted state instantly through the idempotent mutation outbox (the same vote / save / hide / comment-delete pipeline that retries transient failures and rolls back a permanent one); while deleted, the post's title is dimmed and a red "Deleted" marker shows in its attribution.
- **Moderator and admin actions are capability-gated.** The account's moderation capability is fetched from the server when the screen appears (`fetchModerationCapability`). The Moderation submenu only appears when the account moderates this post's community, or is a site admin; otherwise it is absent. A signed-out account never sees it.
- **In-body link preview cards.** Links in post bodies and comment bodies render as a tappable preview card that always shows the link's anchor text (the `[label](url)` text from markdown). For YouTube, Invidious, and PeerTube video links, when the "Load Link Previews" setting is on, the card additionally shows a thumbnail with a play badge and the video title fetched via oEmbed; when the setting is off, the card shows only the anchor text and host. The post-header link card (for link-type posts) always shows the server-provided title and thumbnail regardless of this setting. Tapping a card opens the link through the external-link preference — except a card whose link is a recognized threadiverse post (the frontend form `/c/<community>/p/<id>[/<slug>]` that Lemmy/PieFed/feddit render), which resolves in-app through the shared link router instead of the browser, even on instances outside the Explorer directory (matching how the same link resolves as inline body text). See [External link handling](external-link-handling.md).
- **The post's vote / save / reply / report behaviors** are documented in their own features — see [Voting](voting.md), [Saving](saving.md), [Replying](replying.md), [Sharing](sharing.md).
- **A locked post shows a locked indicator and disables new comments.** The header's metadata line shows a locked glyph and a full-width "Comments are locked" notice appears below the post body; every reply affordance for the post and its comments is hidden, and voting stays fully available. See [Locked posts](locked-posts.md).

## Scenarios

### The post stays pinned above its comments

- **Given** I open a post
- **Then** the post content shows at the top with an inline upvote / downvote / save bar
- **And** the comment tree scrolls below it

### A post with no comments shows the empty state below it

- **Given** I open a post whose comment fetch succeeds with zero comments
- **Then** a "No comments yet / Be the first to comment." placeholder appears directly below the post content
- **And** it is not hidden behind the pinned post header

### A failed comment load shows a truthful offline state, not "No comments yet"

- **Given** I open a post while offline (or the comment fetch otherwise fails) and no comments are on screen
- **Then** the comments region shows an inline failure row — "You're offline" with "Spud will retry automatically when you're back online." (or the unreachable / malformed variant) — and a **Try again** button, never the misleading "No comments yet" empty state
- **When** I tap **Try again**
- **Then** the thread is re-fetched
- **And** if the failure was offline, the thread also re-fetches automatically the moment connectivity returns — without my tapping **Try again** — matching the promise in the message

### A header image that can't load full-res keeps the thumbnail

- **Given** an image post I have already seen in the feed, opened while the full-resolution image can't load (e.g. offline)
- **Then** the header shows the cached thumbnail with a "Low-res preview" pill over it, not a hard "couldn't load" plate
- **When** I tap the pill
- **Then** the full image is retried
- **And** long-pressing the pill offers **Open in browser**

### An inline body image loads without animating the row

- **Given** a post or comment whose body contains a markdown image that hasn't finished loading yet
- **When** the image finishes loading
- **Then** the row snaps instantly to its new height, with no animation
- **And** the image never appears to zoom in from a corner

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

### A busy post shows its comments, not just a count

- **Given** a post whose header reports a large number of comments
- **When** I open it and the comment fetch succeeds
- **Then** the comment tree renders, threaded, down to the depth cutoff
- **And** the tree is not empty while the header reports a non-zero count
- **And** replies below the cutoff are represented by "N more replies" rows rather than being omitted silently

### A truncated thread shows a "load more replies" row

- **Given** a comment reports more replies than the loaded tree carries
- **When** the tree renders
- **Then** a "N more replies" row appears beneath it ("1 more reply" for exactly one)
- **And** the row is not collapsible and has no swipe or long-press actions

### Tapping the row expands the subtree inline

- **Given** a "N more replies" row
- **When** I tap it
- **Then** the row's text is replaced by a spinner while the missing subtree fetches
- **And** on success the fetched replies are spliced in at their correct depth right where the row was, without reloading the rest of the tree
- **When** I tap the row again while it is still loading
- **Then** nothing happens — no second fetch is started

### A subtree deeper than one fetch leaves a fresh "load more" row (self-healing)

- **Given** a "N more replies" row whose subtree is itself deep enough that some of its own descendants still have replies beyond what a single expansion fetches
- **When** the tap's fetch completes
- **Then** the fetched portion is spliced into the tree
- **And** a fresh "N more replies" row appears further down, under whichever descendant still has missing children
- **And** that row is tappable the same way, so a very deep thread expands one layer at a time instead of leaving a stale or broken row

### A failed fetch reverts the row and offers retry

- **Given** a "N more replies" row I have tapped
- **When** the fetch fails (e.g. offline, or the server errors)
- **Then** the row reverts from its spinner back to showing the "N more replies" count
- **And** a "Couldn't load more replies" toast appears
- **When** I tap the row again
- **Then** it retries the fetch

### VoiceOver announces the "load more replies" row's state

- **Given** a "N more replies" row
- **Then** VoiceOver reads it with the hint "Loads more replies"
- **When** the row is loading
- **Then** the hint changes to "Loading replies"

### A comment's context menu

- **Given** another person's comment
- **When** I long-press it
- **Then** I get Upvote, Downvote, Reply, Save, Share, "Remind Me…" (scoped to this
  comment's thread — see [Reminders](reminders.md)), and Report
- **And** Report is omitted on my own comments

### Edit, delete, and restore my own comment

- **Given** my own non-deleted comment
- **When** I long-press it and choose Edit, change the body, and tap Save
- **Then** the new body shows on the comment instantly with an "Edited · Sending…" indicator (votes/score/badges/replies preserved), and the edit is enqueued to the content outbox; on success the server's body replaces the overlay (see [Replying](replying.md))
- **And** choosing Delete (and confirming) instead flips the comment to deleted instantly via the mutation outbox; if it already shows deleted, the menu offers Restore (no confirmation, and no Edit), which flips it back. A permanent server failure rolls a delete/restore back and shows a "Couldn't update comment" toast.

### Edit my own post

- **Given** my own post open in post detail
- **When** I open the "•••" menu, choose Edit, change the title/body/URL/NSFW, and tap Save
- **Then** the header reflects the edit immediately and the change is enqueued to the content outbox; on success the server's version reconciles, and a permanent failure parks it as a failed edit (text kept) for retry
- **And** the community can't be changed while editing

### Delete and restore my own post

- **Given** my own post open in post detail
- **When** I open the "•••" overflow menu and choose Delete, then confirm
- **Then** the post flips to deleted instantly (title dimmed, "Deleted" marker shown) via the mutation outbox, and the menu now offers Restore (no confirmation), which flips it back
- **And** a permanent server failure rolls the change back

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

### Tapping a frontend-post-URL card resolves it in-app

- **Given** a post or comment body containing a threadiverse frontend post link (`/c/<community>/p/<id>[/<slug>]`, e.g. a PieFed or feddit URL)
- **And** the link's instance is not in the bundled Explorer directory
- **When** I tap its preview card
- **Then** the post opens in-app via a federated resolve — the same as tapping the equivalent inline body-text link — rather than bouncing to the browser
- **And** if the post cannot be resolved on the current account it falls back to the external-link preference

### Post-header link card shows server-provided title and thumbnail

- **Given** a link-type post
- **When** I open its detail screen
- **Then** the header shows a link preview card with the server-provided title and thumbnail

### Voting does not flicker the post media

- **Given** I am viewing a post with an image or body link-preview cards
- **When** I upvote, downvote, or save it
- **Then** the action bar and score update in place
- **And** the post image and link-preview cards stay put — no flicker, reload, or reflow

### Collapsing a thread does not flicker images

- **Given** I am viewing a post whose header body and visible comments contain inline images
- **When** I collapse (or expand) a comment thread
- **Then** the header and every visible comment refresh in place
- **And** inline images in the header body and in neighboring comment bodies stay put — no loading-placeholder flash or reload

### A failed inline image offers Retry

- **Given** an inline body image failed to load (e.g. a transient network error)
- **When** I tap **Retry** on its broken-image tile
- **Then** the tile returns to its loading state and the image loads in place — no cell recycle or screen re-entry needed
- **And** **Open in browser** remains available if the load fails again

## Not supported / out of scope

- **No in-screen comment-sort control.** The thread uses the account's default comment sort; there is no per-post picker to re-sort it without changing the global default. (Setting the default lives in Settings.)
- Editing, deleting, and restoring your own *post* are supported via the post overflow / header menu (see above), as is full edit / delete / restore of your own *comment*.
- Collapse state is not persisted: reopening the post starts fully expanded.
- "Load more replies" rows are not collapsible and carry no swipe or long-press actions — tapping the row (to load its subtree) is the only interaction.
- The post is saved from the toolbar or header action bar (or a swipe), not from the post's context menu.
- Swipe-gesture configuration itself is a separate feature — see [swipe-actions.md](swipe-actions.md).
