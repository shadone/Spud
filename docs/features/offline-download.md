# Download a feed for offline browsing

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Feeds and sorting](feeds-and-sorting.md), [Feed loading and pagination](feed-loading.md), [Post detail and comments](post-detail-and-comments.md), [Post thumbnails and media badges](post-thumbnails.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Saves the current feed for reading offline — useful before a flight or a long stretch without a connection. From the feed's Quick Switch (config) popover, "Download for offline" bulk-fetches the top of the feed and everything needed to browse it without a network: the posts, each post's comment tree, and each post's thumbnail and full image. A progress sheet shows the download and can be cancelled. Afterwards, because the feed, post detail, and images all read from the local store / image cache first, the saved content browses normally while offline.

## Behavior and rules

- **Entry point.** "Download for offline" lives in the feed's Quick Switch (config) popover, alongside density / sort. It downloads the feed you're currently viewing (front page, a community, etc.).
- **What gets saved.** Up to a fixed cap of posts from the top of the feed (currently 100) are fetched and persisted; then, for each, its comment tree is fetched and persisted and its thumbnail + full image are fetched into the durable on-disk image cache. Once saved, opening any of those posts offline shows its body, comments, and images.
- **Progress + cancel.** A sheet shows a progress bar and status ("Fetching posts…", then "Saving posts, comments & images — N of M") with a Cancel button. Cancelling (or swiping the sheet away) stops the download promptly; what was already saved remains usable. Only one download runs at a time.
- **Requires a connection to start.** Predownloading needs the network, so the action is unavailable / shows a brief "You're offline" message when there's no connection.
- **Best-effort per post.** A single post whose comments or image fail to download doesn't abort the rest — the download continues and completes with what it could fetch.
- **Polite to the instance.** Comment and image fetches run with a small concurrency limit rather than all at once.
- **Bounded and durable.** The download is capped (it doesn't try to mirror an entire instance), and images live in the app's existing on-disk image cache (about 200 MB, least-recently-used) so they survive relaunch.

## Scenarios

### Save a feed before going offline

- **Given** I'm viewing a feed with a connection
- **When** I open the Quick Switch popover and tap "Download for offline"
- **Then** a progress sheet appears and the feed's posts, comments, and images download
- **And** when it finishes I see a "Saved N posts for offline browsing" confirmation

### Browse the saved feed offline

- **Given** I downloaded a feed and then lost connectivity
- **When** I scroll the feed and open posts
- **Then** the posts, their images, and their comments are shown from the local copy

### Cancel a download

- **Given** a download in progress
- **When** I tap Cancel or swipe the sheet away
- **Then** the download stops and the posts already saved remain available offline

### Can't download while offline

- **Given** I have no connection
- **When** I tap "Download for offline"
- **Then** I'm told I'm offline and no download starts

## Not supported / out of scope

- **It's a point-in-time snapshot, not a sync.** New posts, new comments, and votes that happen after the download are not reflected until you download again (or reconnect and refresh normally).
- **Bounded coverage.** Only the top of the feed (up to the post cap) is saved, not the entire feed history; images are subject to the on-disk cache's size limit, so a very large download may evict the oldest cached images over time.
- **No background or scheduled downloads.** The download runs while the sheet is open; it isn't a background task and isn't scheduled automatically.
- **No separate "offline library" UI.** Saved content is browsed through the normal feed and post screens (which read the local copy when offline) — there is no distinct downloaded-items manager, and no per-download delete beyond the app's normal cache behavior.
- **Writing offline** (voting, commenting, posting) is governed by the existing optimistic/durable outbox, not this feature — actions taken offline queue and send when you reconnect.
