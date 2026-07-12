# Search

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Subscribe / unsubscribe](subscribe-unsubscribe.md), [Community screen](community-screen.md), [Person / user profile](person-profile.md), [Post detail and comments](post-detail-and-comments.md), [Discover (Community Explorer)](discover.md), [Instance picker](instance-picker.md), [NSFW content visibility and blur](nsfw-content.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Search the connected instance for posts, communities, users, or comments — or search the bundled instance directory for an instance. A scope control in the search bar picks which kind you are looking for, and typing runs a debounced query that returns one list at a time. Results render as feed-style rows: a **post row that is the exact same rich cell as the feed** (community@instance handle, score, comment count, thumbnail, status/author badges, and NSFW blur) with an added `@user@instance` author line, a community row with an inline Subscribe button, a user row, a comment-with-context row, or an instance row (icon + name + host + member count). Tapping a result opens the corresponding screen — Post detail, the Community screen, the Person profile, or the in-app instance screen. Search is its own tab, reachable on both iPhone and iPad.

## Behavior and rules

- **Five scopes.** The search bar's scope buttons are Posts, Communities, Users, Comments, and Instances. The active scope decides both how the query is run and which result list is shown. Posts / Communities / Users / Comments each request a Lemmy search type from the connected instance (federated); Instances is searched **client-side** over the bundled Lemmy Explorer directory — Lemmy has no instance search type, so no network request is made for that scope.
- **Instances scope searches the local directory.** Typing in the Instances scope matches the directory's `baseurl` or display name case-insensitively (substring), ranked by total users, capped at the top matches. It does not hit the network and is not affected by the connected instance. Tapping an instance result opens the same in-app instance screen the "Open in Spud" instance row opens.
- **Debounced typing.** Each keystroke schedules the search after a short debounce (about 300 ms); a new keystroke cancels the pending one, so fast typing only ever keeps one request alive. Tapping Search on the keyboard, or changing scope, runs the active query immediately with no debounce.
- **One request at a time.** Every new query or scope change cancels the previous in-flight request before starting the next, so a stale response can never overwrite a newer one.
- **Empty query resets.** Clearing the field (or entering only whitespace) returns the screen to its initial prompt and discards any results.
- **Single page of results.** A search returns one page (up to roughly 30 results) across the All listing, ordered by the server's own default. There is no pagination or infinite scroll on search results.
- **Ordering is server-owned, not a fixed client sort.** Spud does not pin search results to a particular sort (e.g. top-of-all-time) — it omits the sort parameter and lets the connected instance apply its own default. This is deliberate: Lemmy 1.0's search API dropped the sort parameter entirely, so omitting it keeps ordering identical whether the instance speaks the 0.19 (v3) or 1.0 (v4) API. On a v3 instance the server's default is Hot.
- **Designed states.** The screen shows an initial prompt before any query, a spinner while a query is in flight, a no-results state that quotes the term that returned nothing, and an error state if the request fails.
- **Inline subscribe from community results.** A community result row carries a Subscribe / Subscribed button. Tapping it always flips the row in place immediately and durably queues the change without leaving search. If the community is already cached locally (seen before in a feed or another screen), that tap also lands the shared database-backed flip instantly, same as everywhere else; if it was found only through this search, the durable send still fires in the background, but the database catches up once it lands rather than at tap time (see Scenarios and [Subscribe / unsubscribe](subscribe-unsubscribe.md)).
- **Post rows are the shared feed cell.** A post result renders through the same view the feed uses, so a searched post shows the same rich information as in a feed — the `community@instance` handle, score, comment count, thumbnail (image / link preview / video / text placeholder), self-text preview, and the moderation / author-status badges — plus a quiet `@user@instance` author line under the title (which the feed omits). The trailing up/down vote arrows are **not** shown on search rows: a search row taps through to Post detail rather than voting in place. VoiceOver reads the row as one statement including the author.
- **NSFW posts follow the feed.** With "Show NSFW" **on**, an NSFW post result is kept and rendered blurred through the shared cell (respecting the blur preference and tap-to-reveal), exactly as the feed treats NSFW posts. With "Show NSFW" **off**, NSFW posts are dropped from results entirely — matching the feed (which the server filters) — so a user who opted out is never shown NSFW content, raw or blurred. NSFW *communities* are likewise withheld when "Show NSFW" is off. See [NSFW content visibility and blur](nsfw-content.md).
- **Tapping a result navigates.** A post or comment result opens the post in Post detail; a community result opens the [Community screen](community-screen.md); a user result opens the [Person profile](person-profile.md). On a post row, tapping the thumbnail opens the post too (a blurred NSFW thumbnail reveals on the first tap instead).
- **Paste a Lemmy URL to open it in Spud.** When the search field contains a Lemmy link — a post, comment, community, user, or a bare instance — an "Open in Spud" row appears above the results that opens it in-app on tap (resolving the object federally when needed) instead of a web browser. Both canonical URLs (`/post/<id>`, `/c/<name>`, `/u/<name>`, `/comment/<id>`) and the frontend post form some instances use (`/c/<community>/p/<id>/<slug>`) are recognized, including links to instances not in the local directory.
- **Keyboard dismisses on scroll.** Dragging the results list dismisses the keyboard.

## Scenarios

### Search for posts

- **Given** the Search tab with the Posts scope selected
- **When** I type a query and pause
- **Then** after a short debounce the query runs and matching post rows appear
- **And** each row is the same rich feed cell — title, `community@instance` handle, score, comment count, thumbnail, and status/author badges — with a `@user@instance` author line, and no vote arrows

### An NSFW post result is blurred when Show NSFW is on

- **Given** "Show NSFW" is on and the blur preference is on, the Posts scope, and a query that matches an NSFW post
- **When** the results arrive
- **Then** the NSFW post row is shown with its thumbnail blurred (rather than being dropped from the list)
- **And** tapping the blurred thumbnail reveals it for the session

### NSFW posts are hidden when Show NSFW is off

- **Given** "Show NSFW" is off, the Posts scope, and a query that matches an NSFW post
- **When** the results arrive
- **Then** the NSFW post is dropped from the results entirely — never shown, raw or blurred — matching the server-filtered feed
- **And** NSFW communities are likewise withheld from results

### Paste a Lemmy link to open it in Spud

- **Given** the Search tab
- **When** I paste a Lemmy post / community / user / instance URL into the field — including a frontend post URL like `https://feddit.online/c/opensource/p/1784296/favorite-open-source-game`, even for an instance not in my directory
- **Then** an "Open in Spud" row appears
- **And** tapping it opens that content in-app (resolving it federally) rather than in a browser

### Switch scope re-runs the query

- **Given** a query that has returned post results
- **When** I tap the Communities scope
- **Then** the same query runs immediately against communities and the community rows replace the post rows

### Search for an instance

- **Given** the Search tab with the Instances scope selected
- **When** I type an instance name or host (for example `programming.dev`) and pause
- **Then** matching instances from the bundled directory appear, ranked by size, each row showing the instance icon, name, host, and member count
- **And** no network request is made — the directory is searched on-device
- **And** tapping a result opens that instance's in-app screen (the same screen the "Open in Spud" instance row opens)

### Subscribe to a community from a result

- **Given** a community result row showing Subscribe while I am signed in
- **When** I tap Subscribe on that row
- **Then** the row's own button always flips immediately to Subscribed (or Pending), and the change is always durably queued and retried in the background
- **And** if the community is already cached locally (already seen elsewhere, e.g. in a feed), the database-backed state also updates instantly, keeping every other open surface for it in sync; if it was found only through this search, the database instead catches up once the durable send lands
- **And** if the server permanently rejects it, the shared "Couldn't update subscription" toast appears; a cached community's row reverts with the database state, while an uncached one reflects reality the next time the search is re-run or refreshed

### Signed-out subscribe is gated

- **Given** I am browsing search signed out
- **When** I tap Subscribe on a community result
- **Then** a "Sign in to subscribe" alert is shown and no call is made

### Tapping a result opens its screen

- **Given** any result row
- **When** I tap it
- **Then** a post or comment opens the post in Post detail, a community opens the Community screen, a user opens the Person profile, and an instance opens the in-app instance screen

### No results quotes the term

- **Given** a query that matches nothing for the active scope
- **When** the response arrives empty
- **Then** a no-results state is shown quoting the searched term

### A failed search shows an error state

- **Given** the search request fails
- **When** the error returns
- **Then** an error state with a retry message is shown and an alert is surfaced

## Not supported / out of scope

- **NSFW gating mirrors the feed.** With "Show NSFW" off, NSFW posts *and* communities are dropped from results (an opted-out user never sees NSFW). With "Show NSFW" on, NSFW posts are kept and rendered blurred through the shared feed cell (respecting the blur preference and tap-to-reveal), matching the feed. See [NSFW content visibility and blur](nsfw-content.md).
- No pagination on results — search returns a single page; there is no infinite scroll or "load more".
- The result sort is server-defined (not a fixed client sort) and the listing type is fixed to All; there is no in-screen sort or listing picker for search.
- Only community results expose an inline subscribe action; post, user, comment, and instance rows do not.
- **Instances scope is directory-only.** It searches the bundled Lemmy Explorer directory on-device, so it only finds instances present in that directory (Lemmy has no federated instance search). Coverage and freshness follow the directory's seed/refresh, not a live network search.
- No search history, suggestions, or recent-search list.
