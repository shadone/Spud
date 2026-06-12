# Community screen

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Subscribe / unsubscribe](subscribe-unsubscribe.md), [Feeds and sorting](feeds-and-sorting.md), [Feed loading and pagination](feed-loading.md), [Person / user profile](person-profile.md), [Search](search.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

The community screen pins a header above the community's post feed. The header shows the banner, an overlapping circular icon, the title, the canonical `!name@instance` handle, subscriber and post counts, a rendered markdown description, and a state-aware Subscribe / Unsubscribe button. Below it is the same post list used everywhere, scoped to this community, so it loads, sorts, and pages exactly like the main feed. The screen is reached by tapping a community in search, a community link in markdown, or a community in the subscriptions sidebar; it works on iPhone and iPad.

## Behavior and rules

- **Header above a community-scoped feed.** The body is the standard post list driven by a community feed type, embedded below the header. All of [Feed loading and pagination](feed-loading.md) and [Feeds and sorting](feeds-and-sorting.md) applies — first page on appear, cursor-based infinite scroll, default sort.
- **Header is database-driven.** The header fields come from the local database's community observation, so they update live when the community record changes (for example after a subscribe is mirrored back).
- **Resolve-then-show.** Opening a community first resolves its server id (fetching by qualified name when not cached) behind a spinner, then swaps in the header-plus-feed content. A remote community is resolved fully-qualified so any instance can find it.
- **Subscribe / unsubscribe from the header.** The header button toggles subscription, gated on sign-in, via the shared confirm-then-mirror path (see [Subscribe / unsubscribe](subscribe-unsubscribe.md)). The button reflects Subscribe, Subscribed, or Pending from the mirrored state.
- **Header context menu.** Long-pressing the header offers Subscribe / Unsubscribe and Block / Unblock community.
- **New post.** A compose button in the navigation bar opens the new-post composer pre-filled with this community; it is gated on sign-in.
- **Block awareness.** An overflow menu offers Block / Unblock community. The current block state is resolved from the server's block list on appear so the label is correct. Blocking asks for confirmation, then reloads the embedded feed so the now-filtered content disappears; a signed-out block attempt is gated with an alert.
- **Markdown description links.** Links in the description open inline: a person link opens the [Person profile](person-profile.md), a community link opens another Community screen, and other links open externally.
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

- **Given** a community I do not follow, while signed in
- **When** I tap Subscribe in the header
- **Then** the follow is sent and the button reflects Subscribed once the server's result is mirrored back

### Block a community reloads the feed

- **Given** an open community while signed in
- **When** I choose Block community from the overflow menu and confirm
- **Then** the community is blocked and the embedded feed reloads so its posts are filtered out

### Tap a person link in the description

- **Given** a community description containing a user mention
- **When** I tap the mention
- **Then** the Person profile for that user opens

### New post is gated when signed out

- **Given** I am browsing a community signed out
- **When** I tap the compose button
- **Then** a "Sign in to post" alert is shown and the composer does not open

## Not supported / out of scope

- No pull-to-refresh on the community feed — it reloads on sort change, re-selection, or after a block, like the main feed (see [Feed loading and pagination](feed-loading.md)).
- The community feed sort follows the account default; there is no in-screen sort picker on this screen.
- Moderator and admin actions on the community are not provided; the overflow menu offers Block / Unblock only.
- The header shows community metadata but not a moderator list or sidebar rules beyond the markdown description.
