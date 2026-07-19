# Search

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Subscribe / unsubscribe](subscribe-unsubscribe.md), [Community screen](community-screen.md), [Person / user profile](person-profile.md), [Post detail and comments](post-detail-and-comments.md), [Discover (Community Explorer)](discover.md), [Instance picker](instance-picker.md), [NSFW content visibility and blur](nsfw-content.md), [Reminders](reminders.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

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
- **Inline subscribe from community results shows the real, five-state answer.** A community result row's button renders the same Subscribe / Subscribed / Pending / Requested vocabulary the [Community screen](community-screen.md)'s header button does (Requested is v4-only, for a community that gates joining behind moderator approval), sourced from the account's persisted subscribe state, not the search response's own network state — which can be stale or (on a v3 instance) unable to distinguish "the request needs approval" from a plain "subscribed". Tapping the button always flips the row in place immediately (to Pending or back to Subscribe) and durably queues the change without leaving search; the row then live-corrects to the server's confirmed answer once the durable send lands — including staying on Pending / becoming Requested for a community that requires approval, rather than settling on a false "Subscribed". A community found only through this search (not cached locally yet) still gets this live correction once its first database row exists. See Scenarios and [Subscribe / unsubscribe](subscribe-unsubscribe.md).
- **Post rows are the shared feed cell.** A post result renders through the same view the feed uses, so a searched post shows the same rich information as in a feed — the `community@instance` handle, score, comment count, thumbnail (image / link preview / video / text placeholder), self-text preview, and the moderation / author-status badges — plus a quiet `@user@instance` author line under the title (which the feed omits). The trailing up/down vote arrows are **not** shown on search rows: a search row taps through to Post detail rather than voting in place. VoiceOver reads the row as one statement including the author.
- **Post rows carry the full feed long-press menu.** Long-pressing a post result opens the identical context menu the feed uses: Upvote / Downvote, Save, Reply, Share, Cross-post, Visit community, View author, Hide, Block author, Report, and Mute community (with a duration submenu), plus Remind Me when the post is loaded. Every action routes through the same per-account services as the feed (optimistic vote/save via the outbox, sign-in gates on mutating actions, the capability gate on Hide for instances that don't support it).
- **Community rows carry Discover's community context menu, plus "Notify About New Posts."** Long-pressing a community result opens Open Community, Subscribe/Unsubscribe, "Notify About New Posts" (see [Reminders](reminders.md)), Mute (with a duration submenu) or Unmute, Share, Copy Link, and Block Community (destructive) — the same menu Discover's Community Explorer shows, with the notify item added inline after Subscribe/Unsubscribe. The Subscribe/Unsubscribe label reads the same real, persisted-state-wins subscribe state as the row's inline button (so it shows "Unsubscribe" for a Pending or Requested community too, not just a fully-subscribed one), and is re-resolved fresh each time the menu is built — so it reflects a state change (e.g. a Pending that just landed as confirmed) even without a new search. "Notify About New Posts" checkmarks the same way, read fresh from the local follow store at menu-build time. Blocking a community from this menu also removes its notify follow, same as blocking from the community screen. The shared menu builder can also offer "Add to Favorites" / "Remove from Favorites" for a hosting screen that supplies favourite state (the instance-detail screen's meta-community rows do, see [Instance meta communities](instance-meta-communities.md)); Search doesn't supply it, so its own menu never shows that item.
- **Comment rows carry the post detail's comment context menu.** Long-pressing a comment result opens Open Thread, Upvote/Downvote, Save/Unsave, Share, Copy Link, View author, and Report (destructive) — the same primary actions `PostDetailViewController`'s comment context menu offers, dispatched through the same per-account, outbox-backed `LemmyService` comment vote/save calls and the same report call. Own-comment Edit/Delete and moderation are not offered from search (a search result row carries no "is this my comment" or moderation-capability context).
- **User rows carry the Person profile's header long-press actions, plus two for menu-set parity.** Long-pressing a user result opens Open profile, Copy handle, Share, and Block user (destructive). Copy handle and Block/Unblock are the same actions the [Person profile](person-profile.md)'s own header long-press offers; Open profile and Share are added on top so every search result's menu reaches a comparable item set — the profile's own header long-press has neither (Open profile makes no sense when you're already on the profile, and Share lives in its overflow menu instead). Search always offers "Block user" rather than toggling to "Unblock": whether the viewer has already blocked that person can only be learned via a network round trip (the account's block list), which the menu can't afford at long-press time, so it shows the same one-directional action regardless of current state — opening the profile itself resolves and shows the real Block/Unblock state.
- **Instance rows carry a small, directory-appropriate context menu.** Long-pressing an instance result opens Open, Copy Link, Share, and Add Account Here. There is no subscribe/vote/save/block action here — an instance result is a client-side Lemmy Explorer directory row, not a per-viewer server entity, so there is no such state to expose. Add Account Here jumps straight to the login flow for that instance (the same flow the instance screen's own "Log in" and the custom-instance-entry flow use), skipping a trip through the instance screen first.
- **Mutating context-menu actions gate on sign-in; read-only ones don't.** Any action that writes something — vote, save, reply, cross-post, hide, subscribe, mute, block, report — checks sign-in first and shows a "Sign in to …" alert instead of dispatching when signed out, exactly like the equivalent screen's own action. Read-only actions — Open / Visit community / View author, Share, Copy Link / Copy handle — work identically whether signed in or out. The instance menu's Add Account Here has nothing to gate: it *is* a way to sign in.
- **A context-menu mutation doesn't repaint the search row — except a community's subscribe state.** Search renders each row from the search response it fetched, not a live GRDB observation of that row (unlike the feed, Community screen, or Person profile). So voting, saving, muting, or blocking from a result's long-press menu durably queues the change and updates every other surface watching that row through the database, but the search row itself keeps showing what the response returned until the query is re-run — it does not flip in place. **Community subscribe state is the one exception:** Search additionally observes the account's persisted followed-community set live, so a community row's inline button — and the long-press menu's Subscribe/Unsubscribe label, resolved fresh each time it's built — both repaint in place as soon as the outbox's durable subscribe/unsubscribe mirror lands, with no re-search needed. This is what fixes a community requiring moderator approval showing a false "Subscribed" instead of "Pending", and a re-search reverting an already-pending row back to "Subscribe".
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

### Long-press a post result for the feed's context menu

- **Given** a post result row
- **When** I long-press it
- **Then** the same context menu the feed shows opens — Upvote/Downvote, Save, Reply, Share, Cross-post, Visit community, View author, Hide, Block author, Report, Mute community, and Remind Me (when loaded)
- **And** choosing "Visit c/…" or "View u/…" pushes the community or person screen, same as the feed

### Long-press a community result for Discover's community context menu

- **Given** a community result row
- **When** I long-press it
- **Then** a menu opens with Open Community, Subscribe (or Unsubscribe), "Notify About New Posts", Mute (with a duration submenu) or Unmute, Share, Copy Link, and Block Community (destructive) — the same menu Discover's Community Explorer shows, plus the notify item
- **And** choosing "Open Community" pushes the [Community screen](community-screen.md), the same screen a plain row tap opens
- **And** choosing "Subscribe"/"Unsubscribe" from the menu durably queues the change the same way the row's own inline button does, but does not flip the row itself (see "A context-menu mutation doesn't update the search row" below)
- **And** choosing "Notify About New Posts" toggles a standing local follow for that community's new posts (see [Reminders](reminders.md)), independent of Subscribe

### Long-press a comment result for post detail's comment context menu

- **Given** a comment result row
- **When** I long-press it
- **Then** a menu opens with Open Thread, Upvote/Downvote, Save (or Unsave if already saved), Share, Copy Link, View author, and Report
- **And** vote/save/report dispatch through the same per-account `LemmyService` comment calls `PostDetailViewController`'s comment context menu uses, and "Open Thread" opens the comment's parent post in Post detail

### Long-press a user result for its context menu

- **Given** a user result row
- **When** I long-press it
- **Then** a menu opens with Open profile, Copy handle, Share, and Block user (destructive)
- **And** choosing "Open profile" pushes the [Person profile](person-profile.md), the same screen a plain row tap opens
- **And** the menu always offers "Block user", never "Unblock" — Search can't cheaply resolve whether the person is already blocked, so it shows the one-directional action and the profile screen itself reflects the real state

### Long-press an instance result for its context menu

- **Given** an instance result row
- **When** I long-press it
- **Then** a menu opens with Open, Copy Link, Share, and Add Account Here
- **And** choosing "Open" pushes the same in-app instance screen a plain row tap opens
- **And** choosing "Add Account Here" presents the login flow for that instance directly, without first opening the instance screen

### A signed-out mutating context-menu action is gated

- **Given** I am browsing search signed out
- **When** I choose a mutating action from any result's long-press menu — for example Save on a comment result, or Block user on a user result
- **Then** a "Sign in to …" alert is shown and no call is made
- **And** read-only actions in the same menu — Open, Share, Copy Link / Copy handle — still work signed out

### A context-menu mutation doesn't update the search row

- **Given** a comment result row that is not yet saved
- **When** I long-press it and choose Save
- **Then** the save is durably queued the same way a Save from Post detail is, and any other open screen showing that comment updates once it lands
- **And** the search row itself keeps showing its unsaved state until the query is re-run — Search renders the fetched response, not a live observation of the row

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
- **Then** the row's own button always flips immediately to Pending (the state the durable send is about to write), and the change is always durably queued and retried in the background
- **And** once the durable send lands, the row live-corrects to the server's confirmed answer — Subscribed for an open community, or it stays on Pending / becomes Requested for one that requires moderator approval — without needing a new search
- **And** if the server permanently rejects it, the shared "Couldn't update subscription" toast appears and the row reverts to its real persisted-or-network state

### A community requiring approval shows Pending, not a false Subscribed

- **Given** a community result row for a community that requires moderator approval to join
- **When** I tap Subscribe on that row
- **Then** the row shows Pending (or, once the server confirms the approval gate, Requested) rather than settling on a false "Subscribed"
- **And** re-running the same search afterward still shows Pending / Requested — the row does not revert to "Subscribe"

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
- **Community subscribe-state live correction only covers followed communities.** Search observes the account's currently-followed communities (subscribed / pending / requested), so those states repaint live. A community that was denied a follow request, or one unsubscribed from on another screen while its Search row is still on screen, falls back to the search response's own network state until the query is re-run — it isn't live-corrected the way a followed community's Pending → Subscribed transition is.
- **Instances scope is directory-only.** It searches the bundled Lemmy Explorer directory on-device, so it only finds instances present in that directory (Lemmy has no federated instance search). Coverage and freshness follow the directory's seed/refresh, not a live network search.
- No search history, suggestions, or recent-search list.
