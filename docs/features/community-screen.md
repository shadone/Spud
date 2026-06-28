# Community screen

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Subscribe / unsubscribe](subscribe-unsubscribe.md), [Feeds and sorting](feeds-and-sorting.md), [Feed loading and pagination](feed-loading.md), [Person / user profile](person-profile.md), [Search](search.md), [NSFW content visibility and blur](nsfw-content.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

The community screen pins a header above the community's post feed. The header shows the banner, an overlapping circular icon, the title, the canonical `!name@instance` handle, subscriber and post counts, a rendered markdown description, and a state-aware Subscribe / Unsubscribe button. Below it is the same post list used everywhere, scoped to this community, so it loads, sorts, and pages exactly like the main feed. The screen is reached by tapping a community in search, a community link in markdown, a community in the subscriptions sidebar, or a post's context-menu "Visit c/…" action; it works on iPhone and iPad.

## Behavior and rules

- **Header above a community-scoped feed.** The body is the standard post list driven by a community feed type, embedded below the header. All of [Feed loading and pagination](feed-loading.md) and [Feeds and sorting](feeds-and-sorting.md) applies — first page on appear, cursor-based infinite scroll, default sort.
- **Loading skeleton sits below the header.** While the first page loads, the feed's skeleton placeholder is inset to start below the community header rather than behind it, so the opaque header never covers the top skeleton rows. The inset tracks the header's height as it resolves (the community info loads asynchronously).
- **Header is database-driven.** The header fields come from the local database's community observation, so they update live when the community record changes (for example after a subscribe is mirrored back).
- **NSFW badge and blurred banner.** When a community is marked NSFW, its header shows an "NSFW" badge. If "Blur NSFW" is also on, the community banner is covered by a frosted-glass overlay. See [NSFW content visibility and blur](nsfw-content.md).
- **Resolve-then-show.** Opening a community first resolves its server id (fetching by qualified name when not cached) behind a spinner, then swaps in the header-plus-feed content. A remote community is resolved fully-qualified so any instance can find it.
- **Subscribe / unsubscribe from the header.** The header button toggles subscription, gated on sign-in, via the shared confirm-then-mirror path (see [Subscribe / unsubscribe](subscribe-unsubscribe.md)). The button reflects Subscribe, Subscribed, or Pending from the mirrored state.
- **Header context menu.** Long-pressing the header offers Subscribe / Unsubscribe and Block / Unblock community.
- **New post.** A compose button in the navigation bar opens the new-post composer pre-filled with this community; it is gated on sign-in.
- **Sort the feed.** A sort menu in the navigation bar changes the community feed's post sort order — the same grouped Hot / Active / New / Top… pull-down as the main feed. Picking a sort reloads the feed at the new ordering while the header stays in place. See [Feeds and sorting](feeds-and-sorting.md).
- **Overflow menu.** The navigation bar's `•••` menu is grouped into three visually separated sections: (1) Subscribe / Unsubscribe and Add to / Remove from Favorites, (2) Mute and Block, (3) Copy Link, Share…, and Open in Browser. The state-dependent entries are evaluated each time the menu opens so they reflect live subscription, favorite, mute, and block state.
- **Favorites.** Add to / Remove from Favorites is a local, per-account concern (not server-backed, like muting), so it is not gated on sign-in. A favorited community is pinned to the top of the Communities list and flagged with a star (see [Subscriptions sidebar](subscriptions-sidebar.md)).
- **Sharing actions.** Copy Link copies the community's canonical URL, Share… opens the system share sheet (anchored to the overflow button on iPad), and Open in Browser opens that URL externally. The three are omitted when the community has no valid URL yet.
- **Block awareness.** The overflow menu offers Block / Unblock community. The current block state is resolved from the server's block list on appear so the label is correct. Blocking asks for confirmation, then reloads the embedded feed so the now-filtered content disappears; a signed-out block attempt is gated with an alert.
- **Markdown description links.** Links in the description open in-app: a person mention opens the [Person profile](person-profile.md), a community link opens another Community screen, and other Lemmy links (posts, instances, and federated mentions that need resolving) are routed in-app through the shared link router. Only non-Lemmy web links open externally.
- **Title in the nav bar.** The navigation bar title is set to the community title once loaded.

## Scenarios

### Open a community shows header and feed

- **Given** a community I tapped from search, a link, or the sidebar
- **When** the screen resolves
- **Then** a header with banner, icon, title, `!name@instance` handle, subscriber / post counts, and description appears above the community's post feed

### The feed behaves like any feed

- **Given** an open community screen
- **When** I scroll the post list
- **Then** it loads its first page on appear and pages with infinite scroll, at my default sort, like the main feed

### Subscribe from the header

- **Given** a community I do not subscribe to, while signed in
- **When** I tap Subscribe in the header
- **Then** the subscribe is sent and the button reflects Subscribed once the server's result is mirrored back

### Block a community reloads the feed

- **Given** an open community while signed in
- **When** I choose Block community from the overflow menu and confirm
- **Then** the community is blocked and the embedded feed reloads so its posts are filtered out

### Favorite a community pins it in the Communities list

- **Given** an open community I am subscribed to
- **When** I choose Add to Favorites from the overflow menu
- **Then** the community is marked favorite and moves to the top of the Communities list with a star, with no sign-in required

### Share a community from the overflow menu

- **Given** an open community
- **When** I choose Share… from the overflow menu
- **Then** the system share sheet opens for the community's URL (anchored to the overflow button on iPad)

### Tap a person link in the description

- **Given** a community description containing a user mention
- **When** I tap the mention
- **Then** the Person profile for that user opens in-app (not the browser)

### Change the community feed sort

- **Given** an open community screen
- **When** I pick a different sort from the navigation bar sort menu
- **Then** the feed reloads at the new sort while the header stays in place

### New post is gated when signed out

- **Given** I am browsing a community signed out
- **When** I tap the compose button
- **Then** a "Sign in to post" alert is shown and the composer does not open

## Not supported / out of scope

- No pull-to-refresh on the community feed — it reloads on sort change, re-selection, or after a block, like the main feed (see [Feed loading and pagination](feed-loading.md)).
- The community feed sort starts at the account default; a navigation-bar sort menu lets you change it per visit (the choice is not persisted as a new default).
- Moderator and admin actions on the community are not provided; the overflow menu offers subscribe, favorite, mute, block, and the sharing actions only.
- The header shows community metadata but not a moderator list or sidebar rules beyond the markdown description.
