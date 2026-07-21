# Locked posts

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Replying](replying.md), [Post detail and comments](post-detail-and-comments.md), [Moderator / admin actions](moderation-actions.md), [Voting](voting.md)

## What it does

A post a moderator has locked shows a small locked indicator wherever it appears, and
its open detail screen adds a full-width notice explaining that new comments and replies
are off. Every reply affordance for that post and its comments is hidden rather than
shown-disabled, so there's nothing to tap into a dead end. Voting, saving, hiding,
sharing, and editing your own existing comment all keep working normally — locking a
post only turns off *new* commenting.

## Behavior and rules

- **Locked indicator everywhere the post appears.** A yellow lock glyph shows in the
  post's metadata line in the feed, in search results, and on a profile's Posts tab, and
  in the post-detail header's metadata line. VoiceOver announces it as "Locked".
- **Locked notice on post detail.** Opening a locked post additionally shows a full-width
  notice card below the post body, titled "Comments are locked" with the message "New
  comments and replies are turned off. You can still vote." Both the header glyph and the
  notice update live if a moderator locks or unlocks the post while the screen is open —
  no re-navigation needed.
- **Reply affordances are hidden, not disabled, on a locked post.** This applies on every
  surface: the post-detail overflow menu's "Add comment", each comment's swipe action and
  long-press "Reply" on post detail, and the post's own swipe action and long-press
  "Reply" wherever the post is listed (feed, search results, profile Posts tab).
- **Backstop gate.** If a reply is somehow initiated anyway (e.g. a race between an
  unlock/lock and the affordance being hidden), a "Comments are locked" alert is shown
  instead of the composer — the same title and message as the detail notice.
- **Still fully allowed on a locked post:** upvoting/downvoting the post and its existing
  comments, saving, hiding, and sharing the post, and editing your own existing comment.
  Locking only blocks *new* comments and replies — voting is never affected.
- **No in-app moderator bypass.** A moderator who wants to comment on a post they've
  locked must first unlock it via the existing Lock/Unlock moderation action (see
  [Moderator / admin actions](moderation-actions.md)), then reply normally. There is no
  special client-side path around the gate for moderators.

## Scenarios

### The locked notice appears on post detail

- **Given** a locked post
- **When** I open its detail screen
- **Then** the header's metadata line shows the locked glyph
- **And** a full-width "Comments are locked" notice appears below the post body with the
  message "New comments and replies are turned off. You can still vote."

### The feed shows the locked glyph

- **Surfaces:** `iphone`, `ipad`
- **Given** a locked post appears in the feed, search results, or a profile's Posts tab
- **Then** its metadata line shows a yellow lock glyph
- **And** VoiceOver announces "Locked"

### Reply affordances are absent when a post is locked

- **Given** a locked post open in post detail
- **When** I open the overflow menu, or long-press a comment, or swipe on a comment
- **Then** there is no "Add comment" / "Reply" action offered
- **And** the same is true for the post's own swipe and long-press "Reply" wherever it's
  listed (feed, search, profile Posts tab)

### Voting still works when a post is locked

- **Given** a locked post open in post detail
- **When** I upvote or downvote the post, or upvote or downvote one of its comments
- **Then** the vote is applied normally, exactly as on an unlocked post

### A moderator unlock re-enables replying live

- **Given** a locked post open in post detail
- **When** a moderator unlocks it while the screen is open
- **Then** the locked glyph and the "Comments are locked" notice disappear without
  reopening the screen
- **And** the reply affordances (overflow "Add comment", comment Reply) reappear

## Not supported / out of scope

- **Comment-level locking** — a newer server-side concept where an individual comment's
  subtree can be locked independently of the post — is not surfaced; Spud only reflects
  whole-post locking.
- **No client-side moderator bypass.** There is no way to comment on a locked post from
  within the app without first unlocking it through the moderation action; the gate
  applies equally to moderators and ordinary accounts.
