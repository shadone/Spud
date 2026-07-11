# Download a feed for offline browsing

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Feeds and sorting](feeds-and-sorting.md), [Feed loading and pagination](feed-loading.md), [Post detail and comments](post-detail-and-comments.md), [Post thumbnails and media badges](post-thumbnails.md), [External link handling](external-link-handling.md), [Diagnostics logging](diagnostics-logging.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Saves the current feed for reading offline — useful before a flight or a long stretch without a connection. From the feed's Quick Switch (config) popover, "Download for offline" opens a short options sheet (how many posts; whether to also save linked web pages), then bulk-fetches everything needed to browse the feed without a network: the posts, each post's comment tree, and each post's thumbnail and full image — and, optionally, a snapshot of each external link's web page. A small, non-blocking progress pill floats at the bottom of the screen showing the download — you dismiss the options sheet and keep using the app while it runs; the pill stays put as you switch feeds and tabs, and its ✕ cancels. Afterwards, because the feed, post detail, and images all read from the local store / image cache first, the saved content browses normally while offline.

## Behavior and rules

- **Entry point.** "Download for offline" lives in the feed's Quick Switch (config) popover, alongside density / sort. It downloads the feed you're currently viewing (front page, a community, etc.).
- **Choose how much.** Tapping it opens an options sheet where you pick the number of posts to save — **100 (default), 250, or 500** — and toggle **"Also save linked web pages"** (off by default). The choices are remembered for next time.
- **What gets saved.** The chosen number of posts from the top of the feed are fetched and persisted; then, for each, its comment tree is fetched and persisted and its thumbnail + full image are warmed into the durable on-disk image cache. With "save linked web pages" on, each post that links to an external article also has that page snapshotted (a web archive) and stored. Once saved, opening any of those posts offline shows its body, comments, and images — and its linked article, if saved.
- **Reaches the number you asked for.** Paging stops when it has the requested count, the feed genuinely ends, or (backstop) a page budget is hit — and it keeps going past a page that only repeats posts you'd already loaded by scrolling (so starting a 500-post download after browsing the top of the feed still fetches 500, not just what was on screen).
- **Reading saved links offline.** When you're offline and tap a saved post's external link, it opens in an in-app reader showing the saved snapshot (marked "Saved offline"), with Share and "Open in Browser" actions. When you're online, links open the live page as usual — the snapshot is a no-connection fallback, not a replacement. Offline links that weren't saved show a brief "This page isn't saved for offline" note.
- **Non-blocking progress.** A persistent pill anchored to the bottom of the window shows a progress ring and status ("Fetching posts…", then "Saving posts, comments & images — N of M"). It does **not** block the app: after tapping Download you dismiss the options sheet and keep browsing, and the pill stays visible as you switch feeds and switch tabs. It is **not** cancelled by navigating away — only its ✕ cancels. Cancelling stops the download promptly (the pill briefly reads "Cancelling…"); what was already saved remains usable. When the download ends, the pill animates away and a brief toast confirms the outcome ("Saved N posts for offline browsing", or the cancel / failure message). Only one download runs at a time.
- **Requires a connection to start.** Predownloading needs the network, so the action shows a brief "You're offline" message and doesn't start when there's no connection.
- **Best-effort per post.** A single post whose comments, image, or linked page fail to download doesn't abort the rest — the download continues and completes with what it could fetch. A transient failure (a timeout or a server "busy"/"slow down") is retried a few times with a growing back-off before the post is given up on.
- **Survives a bad patch, keeps what it got.** If a feed page keeps failing even after retries, the download stops paging but keeps every post it already saved, downloads their content, and finishes — telling you it couldn't reach the whole feed (e.g. "Downloaded 80 posts — some of the feed couldn't be reached.") rather than throwing everything away. Only a failure on the very first page (nothing saved yet) reports an outright failure.
- **Polite to the instance.** Requests are spaced out so a download never floods the server, comment and image fetches run with a small concurrency limit rather than all at once, and when the server signals it's overloaded (HTTP 429/503) the download briefly backs the whole run off before continuing. Web-page snapshots are captured one at a time.
- **Bounded and durable.** The post count is capped at your choice; images live in the app's existing on-disk image cache (about 200 MB, least-recently-used); saved web pages are bounded by their own cache (about 150 MB, oldest evicted first). All survive relaunch.
- **Diagnosable after the fact.** Each run records curated events to the durable diagnostic log (see [Diagnostics logging](diagnostics-logging.md)): a start and a finish summary. The finish summary carries run-wide aggregate counts of how many individual image warms failed (`imageWarmFailures`) and how many linked-page snapshots failed (`archiveCaptureFailures`), so a download that quietly missed some media is still explainable — without one durable row per image (those per-item failures go to the system log only). Automatic retries are recorded too, tagged by phase (fetching feed pages vs. downloading a post's comments) and flagged when the server asked the app to slow down (a 429/503/rate-limit `pushback`), so a slow or partial download can be understood later from the logs.

## Scenarios

### Choose how much to save

- **Given** I'm viewing a feed with a connection
- **When** I open the Quick Switch popover and tap "Download for offline"
- **Then** an options sheet lets me pick 100 / 250 / 500 posts and toggle "Also save linked web pages"
- **And** tapping Download starts the download with my choices (remembered next time)

### Save a feed before going offline

- **Given** the options sheet with 500 posts selected
- **When** I tap Download
- **Then** a non-blocking progress pill appears and the feed's posts, comments, and images download up to 500
- **And** I can dismiss the options sheet and keep using the app (switching feeds and tabs) while the pill keeps showing progress
- **And** when it finishes the pill animates away and I see a "Saved N posts for offline browsing" confirmation

### Browse the saved feed offline

- **Given** I downloaded a feed and then lost connectivity
- **When** I scroll the feed and open posts
- **Then** the posts, their images, and their comments are shown from the local copy

### Read a saved linked article offline

- **Given** I downloaded the feed with "Also save linked web pages" on, then went offline
- **When** I tap a post's external link
- **Then** the saved page opens in an in-app reader marked "Saved offline"

### Cancel a download

- **Given** a download in progress, its pill showing at the bottom of the screen
- **When** I tap the pill's ✕
- **Then** the download stops and the posts already saved remain available offline

### Keep using the app while a download runs

- **Given** a download in progress
- **When** I switch feeds and switch to another tab
- **Then** the progress pill stays visible and keeps updating, and the download keeps running (dismissing or navigating away does not cancel it)

### Diagnose a download that missed some media

- **Given** I ran an offline download over a flaky connection and some images or linked pages failed to save
- **When** I later open Settings → About → Logs → Event Log and find the download's finish summary
- **Then** it reports aggregate counts of the failed image warms and linked-page snapshots (rather than one row per item), and any retries are tagged with their phase and whether the server was rate-limiting — so I can see what the download couldn't reach and why

### Can't download while offline

- **Given** I have no connection
- **When** I tap "Download for offline"
- **Then** I'm told I'm offline and no download starts

### A flaky connection during a download

- **Given** a download that has already saved some of the feed
- **When** a later page keeps failing even after automatic retries
- **Then** the download stops paging but keeps and finishes the posts it already saved
- **And** the pill animates away and a toast notes that not all of the feed could be reached (not an error that discards everything)

## Not supported / out of scope

- **It's a point-in-time snapshot, not a sync.** New posts, new comments, and votes that happen after the download are not reflected until you download again (or reconnect and refresh normally). Saved web pages are likewise frozen snapshots.
- **In-page links inside a saved article need a connection.** The offline reader shows the saved page; tapping a link within it opens the live web (in the browser), so it won't load while offline.
- **Bounded coverage.** Only the top of the feed (up to the chosen count) is saved, not the entire feed history; images and saved pages are each subject to their cache's size limit, so a very large download may evict the oldest cached items over time.
- **No background or scheduled downloads.** The download runs while the app is in the foreground (it survives dismissing the options sheet, switching feeds, and switching tabs, but it isn't an OS background task and isn't scheduled automatically). It's cancelled if the feed's screen is torn down under memory pressure.
- **No separate "offline library" UI.** Saved content is browsed through the normal feed and post screens (which read the local copy when offline) — there is no distinct downloaded-items manager, and no per-download delete beyond the app's normal cache behavior.
- **Writing offline** (voting, commenting, posting) is governed by the existing optimistic/durable outbox, not this feature — actions taken offline queue and send when you reconnect.
