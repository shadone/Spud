# Feed loading and pagination

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [feeds-and-sorting.md](feeds-and-sorting.md), [mark-read-and-hiding.md](mark-read-and-hiding.md), [Empty, error, and loading states](empty-error-loading-states.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

A feed loads its first page automatically when it has nothing to show, then keeps loading more as you scroll toward the bottom — cursor-based infinite scroll, with a spinner in a footer row while the next page is in flight. Pull down to refresh the feed in place. When the first load fails, the list shows a designed offline / unreachable / malformed state instead of an alert, and it retries automatically once connectivity returns.

## Behavior and rules

- **Cursor-based pagination.** Each page request carries the cursor returned by the previous page; the first request sends no cursor (the head of the feed). The server's response supplies the next cursor, which Spud stores for the following page. A nil cursor in a response means the feed is exhausted and no further pages are fetched.
- **First page on appear.** When the feed has no rows yet, Spud fetches the first page automatically. A feed that already has rows does not refetch on appear.
- **Infinite scroll trigger.** As you scroll, once you pass roughly the last tenth of the content (the scrolled fraction exceeds 0.9), Spud requests the next page. The request fires only when a fetch is not already in flight and the feed is not exhausted.
- **Footer spinner.** While the next page is loading, a footer row with an activity indicator appears below the posts. It is removed once the fetch completes.
- **One fetch at a time.** A new page request is skipped while one is already running, so a fast scroll cannot stack duplicate fetches.
- **Reload resets to the head.** Reloading a feed (changing sort, re-selecting it from the sidebar, or a programmatic reload after blocking a user or community) builds a fresh feed, clears the cursor, and fetches from the top again.
- **Empty state.** Once the first snapshot has arrived and the feed is genuinely empty (and nothing is fetching), the list shows an empty-state placeholder with an icon, title, and message. It is suppressed during the initial and in-flight loads so it never flashes before content arrives.
- **Pull-to-refresh.** Pulling the list down refreshes the feed in place: a refresh spinner overlays the existing posts. On success the list updates; on failure a toast is shown and the existing posts stay — the feed does not drop into an error state when it already has content.
- **Initial-load states.** Before the first page arrives the list shows a shimmer skeleton. If the first load fails, the feed renders a designed inline state classified as **Offline**, **Unreachable**, or **Malformed** (each with its own copy and a retry affordance) rather than an alert. A slow first load shows a "slow connection" hint after a few seconds, and the attempt times out at ~25 s into the Unreachable state.
- **Automatic retry on reconnect.** A reachability monitor (`NWPathMonitor`) watches connectivity; after an offline failure the feed re-fetches automatically once the network is back.
- **Pagination failures are non-destructive.** A failed next-page fetch shows a toast and leaves the loaded posts intact; the footer spinner is removed.

## Scenarios

### First page loads automatically

- **Given** a feed I just opened that has no posts yet
- **When** the list appears
- **Then** Spud fetches the first page from the server
- **And** the posts populate the list

### Infinite scroll loads the next page

- **Given** a feed showing its first page
- **When** I scroll past roughly the last tenth of the content
- **Then** a footer spinner appears and the next page is fetched
- **And** the new posts are appended below

### The footer spinner shows while paging

- **Given** the next page is being fetched
- **When** I look at the bottom of the list
- **Then** a row with an activity indicator is shown
- **And** it disappears once the page arrives

### A scroll burst does not double-fetch

- **Given** a page fetch is already in flight
- **When** I keep scrolling to the bottom
- **Then** no additional fetch is started until the current one finishes

### The feed stops paging when exhausted

- **Given** a feed whose last page returned no next cursor
- **When** I scroll to the bottom again
- **Then** no further fetch is made

### An empty feed shows a placeholder

- **Given** the first page returned no posts
- **When** the list settles
- **Then** an empty-state icon, title, and message are shown

### Pull to refresh

- **Given** a feed with posts already loaded
- **When** I pull the list down
- **Then** a refresh spinner overlays the posts and the feed reloads in place
- **And** if the refresh fails, a toast appears and my existing posts remain

### The first load fails offline

- **Given** I open a feed with no network
- **When** the first page fails
- **Then** the list shows an Offline state (not an alert), and it retries automatically when connectivity returns

## Not supported / out of scope

- No manual "load more" button — paging is automatic on scroll.
- No background or periodic feed refresh; a feed only fetches on first appear, on scroll, or on an explicit reload.
- Pagination is opaque-cursor based; Spud does not expose page numbers and cannot jump to an arbitrary page.
