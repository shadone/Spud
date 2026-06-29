# Download a feed for offline browsing

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Feeds and sorting](feeds-and-sorting.md), [Feed loading and pagination](feed-loading.md), [Post detail and comments](post-detail-and-comments.md), [Post thumbnails and media badges](post-thumbnails.md), [External link handling](external-link-handling.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Saves the current feed for reading offline — useful before a flight or a long stretch without a connection. From the feed's Quick Switch (config) popover, "Download for offline" opens a short options sheet (how many posts; whether to also save linked web pages), then bulk-fetches everything needed to browse the feed without a network: the posts, each post's comment tree, and each post's thumbnail and full image — and, optionally, a snapshot of each external link's web page. A progress sheet shows the download and can be cancelled. Afterwards, because the feed, post detail, and images all read from the local store / image cache first, the saved content browses normally while offline.

## Behavior and rules

- **Entry point.** "Download for offline" lives in the feed's Quick Switch (config) popover, alongside density / sort. It downloads the feed you're currently viewing (front page, a community, etc.).
- **Choose how much.** Tapping it opens an options sheet where you pick the number of posts to save — **100 (default), 250, or 500** — and toggle **"Also save linked web pages"** (off by default). The choices are remembered for next time.
- **What gets saved.** The chosen number of posts from the top of the feed are fetched and persisted; then, for each, its comment tree is fetched and persisted and its thumbnail + full image are warmed into the durable on-disk image cache. With "save linked web pages" on, each post that links to an external article also has that page snapshotted (a web archive) and stored. Once saved, opening any of those posts offline shows its body, comments, and images — and its linked article, if saved.
- **Reaches the number you asked for.** Paging stops when it has the requested count, the feed genuinely ends, or (backstop) a page budget is hit — and it keeps going past a page that only repeats posts you'd already loaded by scrolling (so starting a 500-post download after browsing the top of the feed still fetches 500, not just what was on screen).
- **Reading saved links offline.** When you're offline and tap a saved post's external link, it opens in an in-app reader showing the saved snapshot (marked "Saved offline"), with Share and "Open in Browser" actions. When you're online, links open the live page as usual — the snapshot is a no-connection fallback, not a replacement. Offline links that weren't saved show a brief "This page isn't saved for offline" note.
- **Progress + cancel.** A sheet shows a progress bar and status ("Fetching posts…", then "Saving posts, comments & images — N of M") with a Cancel button. Cancelling (or swiping the sheet away) stops the download promptly; what was already saved remains usable. Only one download runs at a time.
- **Requires a connection to start.** Predownloading needs the network, so the action shows a brief "You're offline" message and doesn't start when there's no connection.
- **Best-effort per post.** A single post whose comments, image, or linked page fail to download doesn't abort the rest — the download continues and completes with what it could fetch.
- **Polite to the instance.** Comment and image fetches run with a small concurrency limit rather than all at once; web-page snapshots are captured one at a time.
- **Bounded and durable.** The post count is capped at your choice; images live in the app's existing on-disk image cache (about 200 MB, least-recently-used); saved web pages are bounded by their own cache (about 150 MB, oldest evicted first). All survive relaunch.

## Scenarios

### Choose how much to save

- **Given** I'm viewing a feed with a connection
- **When** I open the Quick Switch popover and tap "Download for offline"
- **Then** an options sheet lets me pick 100 / 250 / 500 posts and toggle "Also save linked web pages"
- **And** tapping Download starts the download with my choices (remembered next time)

### Save a feed before going offline

- **Given** the options sheet with 500 posts selected
- **When** I tap Download
- **Then** a progress sheet appears and the feed's posts, comments, and images download up to 500
- **And** when it finishes I see a "Saved N posts for offline browsing" confirmation

### Browse the saved feed offline

- **Given** I downloaded a feed and then lost connectivity
- **When** I scroll the feed and open posts
- **Then** the posts, their images, and their comments are shown from the local copy

### Read a saved linked article offline

- **Given** I downloaded the feed with "Also save linked web pages" on, then went offline
- **When** I tap a post's external link
- **Then** the saved page opens in an in-app reader marked "Saved offline"

### Cancel a download

- **Given** a download in progress
- **When** I tap Cancel or swipe the sheet away
- **Then** the download stops and the posts already saved remain available offline

### Can't download while offline

- **Given** I have no connection
- **When** I tap "Download for offline"
- **Then** I'm told I'm offline and no download starts

## Not supported / out of scope

- **It's a point-in-time snapshot, not a sync.** New posts, new comments, and votes that happen after the download are not reflected until you download again (or reconnect and refresh normally). Saved web pages are likewise frozen snapshots.
- **In-page links inside a saved article need a connection.** The offline reader shows the saved page; tapping a link within it opens the live web (in the browser), so it won't load while offline.
- **Bounded coverage.** Only the top of the feed (up to the chosen count) is saved, not the entire feed history; images and saved pages are each subject to their cache's size limit, so a very large download may evict the oldest cached items over time.
- **No background or scheduled downloads.** The download runs while the sheet is open; it isn't a background task and isn't scheduled automatically.
- **No separate "offline library" UI.** Saved content is browsed through the normal feed and post screens (which read the local copy when offline) — there is no distinct downloaded-items manager, and no per-download delete beyond the app's normal cache behavior.
- **Writing offline** (voting, commenting, posting) is governed by the existing optimistic/durable outbox, not this feature — actions taken offline queue and send when you reconnect.
