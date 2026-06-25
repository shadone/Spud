# Subscriptions sidebar

- **Surfaces:** `ipad`
- **Status:** shipped
- **Related:** [Feeds and sorting](feeds-and-sorting.md), [Subscribe / unsubscribe](subscribe-unsubscribe.md), [Community screen](community-screen.md), [Saving](saving.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

The Posts tab is a split view whose primary column is a sidebar listing the standard feeds (Subscribed, Local, All), your Saved posts, and the communities you are subscribed to. Tapping a feed entry opens that feed in the post list; tapping a community opens the full [Community screen](community-screen.md). On a regular-width iPad the sidebar sits beside the post list as a persistent column. On a compact iPhone the split view collapses to a single column showing the post list, and the sidebar is the screen behind it in the navigation stack — reachable with the back button, not as a top-level destination.

## Behavior and rules

- **It is the primary column of the Posts split view.** The post list navigation stack is rooted at the sidebar with the default feed pushed on top, so the sidebar is always one level below the post list.
- **Standard feed entries.** The sidebar always offers Local (posts from your home instance) and All (posts from all federated instances). Subscribed (posts from your subscriptions) is offered only when signed in.
- **Saved entry, signed in only.** A Saved entry, listing posts you have saved, is shown only for a signed-in account — saved posts require authentication. See [Saving](saving.md).
- **Subscribed communities section.** When you follow any communities, a "Subscribed communities" section lists them, each as an icon-plus-name row. The list is driven live from the local database's followed-communities observation, so subscribing or unsubscribing elsewhere updates it without a manual refresh.
- **Favorites pinned to the top.** Communities you have favorited (from the Community screen's overflow menu) are pinned above the rest of the list and flagged with a filled star, sorted among themselves by the active sort. Favorites are a local, per-account concern, driven live from the favorited-communities observation, so toggling a favorite re-pins the row without a manual refresh. A favorited community you are not subscribed to does not appear here — the list only pins among the communities it already shows.
- **Feed entries open the post list.** Tapping Subscribed, Local, All, or Saved builds the matching feed at your default sort and pushes the post list. The selected feed loads and pages like any other (see [Feeds and sorting](feeds-and-sorting.md)).
- **Community entries open the Community screen.** Tapping a subscribed community opens the full Community screen — header plus feed — rather than a bare post list, so subscribe / unsubscribe and the community header are available from the sidebar path too.
- **Regular vs compact.** On a regular-width split (iPad) the sidebar and post list are side by side. On compact width (iPhone, or a narrow iPad multitasking split) the columns collapse into one navigation stack; the post list is shown and the sidebar is the previous screen.

## Scenarios

### The sidebar lists feeds and subscribed communities

- **Surfaces:** `ipad`
- **Given** I am signed in with several subscribed communities, on iPad
- **When** I look at the primary column of the Posts tab
- **Then** I see Subscribed, Local, All, a Saved entry, and a "Subscribed communities" section listing my communities

### Open a standard feed from the sidebar

- **Surfaces:** `ipad`
- **Given** the sidebar
- **When** I tap All
- **Then** the All feed opens in the post list at my default sort

### Open a subscribed community from the sidebar

- **Surfaces:** `ipad`
- **Given** the "Subscribed communities" section
- **When** I tap a community
- **Then** the full Community screen opens, with its header and community feed

### Signed-out hides Subscribed and Saved

- **Surfaces:** `ipad`
- **Given** I am browsing signed out
- **When** I look at the sidebar
- **Then** Local and All are shown but Subscribed and Saved are not

### Subscribing elsewhere updates the list

- **Surfaces:** `ipad`
- **Given** the sidebar with the "Subscribed communities" section visible
- **When** I subscribe to a new community from the Community screen or search
- **Then** that community appears in the section without a manual refresh

### Favorites pin to the top

- **Surfaces:** `ipad`
- **Given** the "Subscribed communities" section with a community I have favorited
- **When** I look at the list
- **Then** the favorited community appears at the top with a star, above the non-favorited communities

## Not supported / out of scope

- **No iPhone-portrait entry point.** On compact width the split view collapses and presents the post list; the sidebar is only the screen behind it in the navigation stack, not a tab or top-level destination. There is no dedicated subscriptions surface on a compact iPhone, which is why this doc is tagged `ipad` only.
- The sidebar lists communities but does not let you unsubscribe directly from a row — open the community to change subscription (see [Subscribe / unsubscribe](subscribe-unsubscribe.md)).
- No reordering, search, or filtering of the subscribed-communities list.
- The Moderator view listing is not offered in the sidebar.
