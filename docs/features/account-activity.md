# Account Activity

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped (Phase 1)
- **Related:** [Accounts and switching](accounts-and-switching.md), [Saving](saving.md), [Marking posts read and hiding read posts](mark-read-and-hiding.md), [Voting](voting.md)

## What it does

The Activity screen shows a reverse-chronological timeline of everything the signed-in
account has done: posts upvoted or downvoted, comments and posts authored, items saved,
posts read, posts seen, and posts hidden. It supersedes the former History screen.

The screen is reached from the Account tab via three shortcuts — "Activity", "Your posts",
and "Your comments" — each of which opens the same Activity screen but with a different
filter preset active. "Your posts" opens it with the Posts chip on; "Your comments" with
Comments; "Activity" opens it with no chips active (all types shown). The user can freely
toggle any filter chips afterward. (The separate Account → "Saved" row does **not** open
Activity — it opens the authoritative server-backed Saved feed; see below.)

Each item in the timeline consists of a compact action header ("Upvoted · 3h ago") above
either a post row or a comment row so you can see exactly what you acted on. Post rows reuse
the feed's post cell (thumbnail, body preview, vote arrows, NSFW blur, status badges) and
comment rows reuse the search comment cell, so an activity row looks and behaves like its
counterpart elsewhere in the app. Items are grouped by day (Today / Yesterday / day name
within the past week / date string for older), with sticky section headers. A
horizontally-scrollable filter chip bar (led by a funnel reset button) below the navigation
bar lets you narrow the list to one or more action types. A search field narrows by title or
body text. Pull-to-refresh re-fetches authored content, and the list honors the app's
display-density preference. Tapping a row opens the post or comment's post in the detail view.

## Saved is the server feed, not the Activity filter

Activity exposes a **Saved** filter chip, but that view is a *local, best-effort* projection
of saved items on this device — it can lag the server's saved set (e.g. items saved on
another client, or before this device cached them). The authoritative list lives behind the
Account tab's dedicated **"Saved"** row, which opens the server-backed `.saved` feed
(`PostListViewController`), not Activity. The Activity empty state's "See saved" button and
the Account "Saved" row both route there.

## Behavior and rules

- **Timeline sources.** The stream merges two sources: a live local stream (read, seen,
  saved, hidden, voted) from the device database and an authored stream (posts and comments
  you wrote) fetched page-by-page from the server. The merge frontier keeps the visible
  prefix consistent — authored items only appear once their page's oldest timestamp is
  known, preventing out-of-order insertions as pages arrive.

- **Offline.** The local stream (Read, Seen, Saved, Voted, Hidden) is always available from
  the on-device database. The authored stream (Posts, Comments) requires a network
  connection; when offline, authored items from the current session's cache may still appear
  if already fetched, but new pages will not load.

- **Day-based grouping.** Items are bucketed by the `occurredAt` timestamp into sections:
  "Today", "Yesterday", the day-of-week name for items within the past 7 days, or a medium
  date string for older items. Sections carry sticky headers. Each item type uses its own
  timestamp as `occurredAt` (e.g. upvotes use `votedAt`, reads use `lastOpenedAt`, authored
  posts use `published`).

- **Filter bar.** Seven chip toggles correspond to the seven filter types: Posts, Comments,
  Saved, Votes, Read, Seen, Hidden. No chips active means "show all". Enabling one or more
  chips narrows the stream to only those action types. Filters are independent toggles; any
  combination is valid. Changing filters restarts the item stream immediately.

- **Initial filter preset.** The filter bar can be opened with one or more chips pre-active
  (set by the Account tab shortcut that navigated here). The user can add or remove chips
  freely after opening.

- **Read vs Seen.** Read (`lastOpenedAt`) means the post detail was opened; Seen
  (`lastSeenAt`) means the post row was scrolled into the viewport on the feed. They are
  separate filter types and can appear independently in the timeline.

- **Voted items are forward-only.** The Votes filter shows only votes recorded locally
  after the Activity screen was first introduced. Votes cast before that release have no
  local record and do not appear.

- **Search.** The navigation-bar search field filters by title or body text. Queries are
  debounced 250 ms before restarting the stream. Clearing the field restores all items.
  Search and filter chips compose: both are applied simultaneously.

- **Infinite scroll.** Scrolling within 200 pt of the bottom triggers `loadMore()` on the
  coordinator, which fetches the next authored page and lowers the merge frontier so the
  prefix extends. The local stream is always complete; only the authored side paginates.

- **Navigation.** Tapping a post row calls `MainWindow.display(serverPostId:accountKeychainId:)`.
  Tapping a comment row calls the same method with the parent post id and passes
  `scrollToCommentId` so the detail view jumps to the comment.

- **Snapshot-only voted comments can't be opened (Phase-1 limitation).** A comment you
  voted on that isn't in the local cache is reconstructed from the vote-event snapshot,
  which has no parent post id. Such a row still shows its body and score, but tapping it
  does nothing (there's no post to open); its VoiceOver hint says it isn't available to
  open. Once the comment's post is cached, the row becomes tappable.

- **States.** The screen renders distinct states off the coordinator's load state and item
  count:
  - *Loading* — a spinner while the first authored page is in flight and nothing is shown yet.
  - *General empty* ("Your story starts here") — no activity at all, with "Browse communities"
    (switches to the Communities tab) and "See saved" (opens the server Saved feed) buttons.
  - *Voted first run* ("Votes start filling in now") — the Votes filter is active but no votes
    have been recorded yet; the copy is honest about votes being forward-only.
  - *Filtered empty* ("Nothing here yet") — a specific filter matches nothing.
  - *Offline banner* ("You're offline — showing what's on this device") — the authored fetch
    failed (degraded); the local stream keeps showing and a Retry button re-attempts the page.
  - *Sparse-votes banner* — the same "Votes start filling in now" note above a short
    vote-filtered list.

- **Accessibility.** Each timeline row is a single VoiceOver element with a composed label
  ("You upvoted, 2h ago, <title>, in <community>, <score>, <comments>"); the inner cell's
  glyph sub-elements are hidden so score/▲▼ are not read as "black up-pointing triangle".
  Filter chips expose their on/off state via the selected trait and an "On"/"Off" value
  (not by colour alone), with "<name>, filter" labels and a button trait.

- **Account isolation.** The coordinator is constructed for a specific `accountKeychainId`;
  all queries are scoped to that account's person row and account id.

## Scenarios

### Open Activity from Account tab

- **Given** I am signed in
- **When** I tap the Account tab then tap "Activity"
- **Then** the Activity screen pushes onto the navigation stack
- **And** the timeline populates with my recent actions in reverse chronological order
- **And** items are grouped under "Today", "Yesterday", or a date header

### Filter to a single action type

- **Given** I am on the Activity screen
- **When** I tap the "Votes" filter chip
- **Then** only upvoted and downvoted items remain in the list
- **And** the chip appears highlighted (accent fill)

### Add a second filter chip

- **Given** the "Votes" chip is active
- **When** I tap the "Comments" chip
- **Then** both voted and commented items appear in the list

### Remove an active filter

- **Given** the "Votes" chip is active
- **When** I tap "Votes" again
- **Then** the chip deactivates and the list reverts to showing all action types

### Search narrows by text

- **Given** I am on the Activity screen
- **When** I tap the search field and type "mountain"
- **Then** only items whose title or body contains "mountain" are shown
- **And** the filter chips remain applied alongside the search

### Tap a post item to open it

- **Given** I see a post item in my Activity timeline
- **When** I tap it
- **Then** the Post Detail screen opens for that post

### Tap a comment item to jump to the comment

- **Given** I see a comment item in my Activity timeline
- **When** I tap it
- **Then** the Post Detail screen opens for that comment's parent post
- **And** the view scrolls to and highlights that specific comment

### Scroll to load more authored content

- **Given** I have reached the bottom of the Activity timeline
- **When** the list scrolls within 200 pt of the end
- **Then** the next page of authored posts and comments is fetched
- **And** newly loaded items appear above the old bottom as the merge frontier lowers

### Account "Saved" opens the server feed, not Activity

- **Given** I am signed in
- **When** I tap the Account tab then tap "Saved"
- **Then** the server-backed Saved feed opens (the authoritative saved list)
- **And** it is the same feed reachable elsewhere, not the Activity screen's local Saved filter

### Empty timeline offers a way forward

- **Given** I am a brand-new signed-in user with no recorded activity
- **When** I open Activity
- **Then** I see "Your story starts here" with "Browse communities" and "See saved" buttons
- **When** I tap "Browse communities"
- **Then** the Communities tab is selected
