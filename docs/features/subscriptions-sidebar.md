# Communities tab (subscriptions)

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Discover (Community Explorer)](discover.md), [Feeds and sorting](feeds-and-sorting.md), [Subscribe / unsubscribe](subscribe-unsubscribe.md), [Community screen](community-screen.md), [Saving](saving.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

The **Communities** tab is the subscriptions / community-management home — a first-class tab in the tab bar (Posts | Communities | Search | Inbox | Account), reachable on both iPhone and iPad. It lists feed shortcuts (Subscribed, Local, All, and Saved when signed in), an entry into [Discover](discover.md), and the communities you're subscribed to (favorites pinned to the top). A search field filters your communities, and a sort control orders them. (This surface was previously the iPad split-view sidebar; the Scout redesign promoted it to a tab, so it is now reachable on iPhone too.)

## Behavior and rules

- **A first-class tab on every device.** Communities is tab index 1 in the tab bar, present in both compact (iPhone) and regular (iPad) size classes — it is no longer hidden behind the Posts split view.
- **Feed shortcuts.** The list offers Local (your home instance) and All (all federated instances) always, and Subscribed (your subscriptions) when signed in. Tapping one pushes that feed's post list within the Communities tab at your default sort (it pages like any feed — see [Feeds and sorting](feeds-and-sorting.md)).
- **Saved shortcut, signed in only.** A Saved entry (your saved posts) is shown only for a signed-in account; saved posts require authentication. See [Saving](saving.md).
- **Discover entry.** A "Discover communities" entry at the top pushes the [Discover](discover.md) screen for browsing/finding new communities.
- **Subscribed communities section.** When you're subscribed to any communities, a "Subscribed communities" section lists them as icon-plus-name rows, driven live from the local followed-communities observation. Subscribing / unsubscribing elsewhere updates it instantly — the optimistic write lands in the same database transaction the tap makes, before any network round trip, so there's no manual refresh and no wait for the server. Tapping a community opens the full [Community screen](community-screen.md) (header + feed), not a bare post list.
- **Favorites pinned to the top.** Communities you've favorited (from the Community screen's overflow menu) are pinned above the rest with a filled star, driven live from the favorited-communities observation. A favorite you aren't subscribed to isn't shown here — the list only pins among the communities it already shows.
- **Filter your communities.** A "Search your communities" field filters the subscribed list as you type (local, case-insensitive); it does not search the network (that's [Discover](discover.md) / [Search](search.md)).
- **Sort the list.** A sort control orders the communities **Alphabetically** or **By instance**; favorites stay pinned within the chosen order.
- **iPad: also the Posts split.** On iPad the Posts tab is still a two-column split (feed switcher + post list / detail), independent of this tab — see [iPad split-view handoff](ipad-split-view.md). The Communities tab is its own stack on both platforms.

## Scenarios

### The Communities tab lists feeds and subscribed communities

- **Given** I am signed in with several subscribed communities
- **When** I open the Communities tab
- **Then** I see a Discover entry, the Subscribed / Local / All / Saved shortcuts, and a "Subscribed communities" section listing my communities

### Open a standard feed from the tab

- **Given** the Communities tab
- **When** I tap All
- **Then** the All feed opens in a post list at my default sort

### Open a subscribed community

- **Given** the "Subscribed communities" section
- **When** I tap a community
- **Then** the full Community screen opens, with its header and community feed

### Filter and sort the list

- **Given** the Communities tab with many subscriptions
- **When** I type into "Search your communities" or change the sort to By instance
- **Then** the list filters / re-orders accordingly, with favorites pinned at the top

### Signed-out hides Subscribed and Saved

- **Given** I am browsing signed out
- **When** I open the Communities tab
- **Then** Local and All are shown but Subscribed and Saved are not

### Subscribing elsewhere updates the list

- **Given** the "Subscribed communities" section visible
- **When** I subscribe to a new community from the Community screen, Discover, or search
- **Then** that community appears in the section instantly — the same tap that subscribes writes the local state this section observes, with no manual refresh and no wait on the network

## Not supported / out of scope

- The list does not let you unsubscribe directly from a row — open the community to change subscription (see [Subscribe / unsubscribe](subscribe-unsubscribe.md)).
- No manual reordering of the subscribed-communities list (it's sorted Alphabetically / By instance, favorites pinned).
- The Moderator-view feed is not offered as a shortcut here.
