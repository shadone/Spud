# Account Activity

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
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

## Activity Summary screen

From the Activity screen's navigation bar a "Summary" button opens the Summary screen.
The Summary screen presents a statistical overview of the account's activity for roughly
the past 18 weeks (126 days), ending at "today" each time it is opened. It is not a
real-time feed — it is a read-only analytics view driven entirely from the on-device
database.

The screen is a vertically scrollable card stack:

- **Identity strip** — avatar, display name, joined date, and cake day for the
  signed-in account. Populated asynchronously once the account's `person` row is
  available in the database.
- **Stat tiles** — six summary numbers in a 2 × 3 grid, in display order: Posts
  (authored posts), Comments (authored comments), Saved (saved posts and comments),
  Votes cast (total local vote events; forward-only, not backfilled), Communities
  (followed communities), and Posts read (posts where the detail was opened).
  Each tile shows the numeric count and a short label; tiles are read-only.
- **Contribution heatmap card** — a 18 × 7 dot grid (18 weeks, 7 days each, oldest
  week on the left, most-recent week on the right). Each dot's intensity represents the
  count for that day relative to the series' maximum day. A metric segmented control
  (All / Reads / Votes) beneath the grid filters which event type is plotted; switching
  the metric instantly re-renders the dots and updates the running total shown above the
  grid. An empty-votes note ("Votes appear here from now on. Nothing to plot yet.") is
  shown below the control when the Votes metric is selected but no vote events exist in
  the window.
- **Extras tiles** — three small insight tiles: Streak (consecutive days ending at
  today on which any event was recorded), Top community (most-visited community in the
  window), and Busiest time (peak time-of-day band).

The metric selected in the heatmap card persists for the lifetime of the screen but is
not saved across sessions — it resets to "All" on each open. Dynamic Type is fully
supported across all cards.

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

- **Summary — 18-week window.** The heatmap covers the 126 days ending at the `asOf`
  date (today when opened normally). Each column is one calendar week; columns run
  Monday–Sunday. Days in the future (relative to `asOf`) are rendered at zero intensity.

- **Summary — dot intensity.** Each day's dot is drawn at a relative intensity:
  0 events → no fill; 1 or more events → filled at a proportion of the maximum
  single-day count in the current window. Days with the window maximum get full
  intensity. The intensity scale is recomputed each time the metric changes.

- **Summary — streak counting.** The streak is the longest unbroken run of calendar
  days (ending at or before `asOf`) on which at least one event of any type was
  recorded in the on-device database. Only local-database events count; authored content
  not yet fetched from the server does not contribute.

- **Summary — offline.** The Summary screen reads only from the on-device database and
  does not require a network connection. Stat tiles and the heatmap are always populated
  from local data; the identity strip is populated from the cached `person` row.

- **Summary — metric persistence.** The selected metric (All / Reads / Votes) is
  per-session only; it resets to All each time the Summary screen is pushed.

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

### Open Summary from Activity

- **Given** I am on the Activity screen
- **When** I tap the "Summary" navigation bar button
- **Then** the Summary screen pushes onto the navigation stack
- **And** the stat tiles show my all-time local counts
- **And** the heatmap shows 18 weeks of "All" activity with dot intensity proportional to event count
- **And** the identity strip shows my avatar, display name, joined date, and cake day

### Switch heatmap metric to Votes

- **Given** I am on the Summary screen
- **When** I tap the "Votes" segment in the metric control beneath the heatmap
- **Then** the heatmap re-renders to show only vote events
- **And** the running total above the grid updates to the vote count for the window
- **And** if I have no vote events, the "Votes appear here from now on. Nothing to plot yet." note appears below the control

### Switch heatmap metric back to All

- **Given** the Summary screen is showing the "Votes" metric
- **When** I tap the "All" segment
- **Then** the heatmap reverts to combining all event types
- **And** the total and dot intensities update accordingly

### Summary is available offline

- **Given** I have previously used the app and have locally stored activity
- **And** my device is offline
- **When** I open the Summary screen
- **Then** the stat tiles, heatmap, and extras tiles all populate from local data
- **And** no network-error state is shown (the screen does not make any network requests)

### Dynamic Type enlarges all Summary cards

- **Given** I have set a large accessibility text size in iOS Settings
- **When** I open the Summary screen
- **Then** all text in the identity strip, stat tiles, heatmap card, and extras tiles
       scales with the system text size
- **And** the layout remains readable and no text is clipped
