# Feeds and sorting

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [feed-loading.md](feed-loading.md), [post-thumbnails.md](post-thumbnails.md), [mark-read-and-hiding.md](mark-read-and-hiding.md), [nsfw-content.md](nsfw-content.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Spud's post list shows one feed at a time: a frontpage listing (All, Local, or Subscribed), a single community's posts, or your saved posts. Every feed is sortable from a menu in the navigation bar, and the Top sort expands into a set of time ranges. The same `PostListViewController` renders all of them — the community screen and the saved feed embed or push the very same list.

## Behavior and rules

- **Three frontpage listing types.** A frontpage feed is one of All, Local, or Subscribed (the `ListingType` cases All / Local / Subscribed). The navigation title reflects the active listing — "All", "Local", or "Subscribed".
- **The frontpage starts on your default listing.** On launch the post list opens a default feed whose listing type comes from your account's preferred listing, falling back to the instance's default, then to All.
- **Switching listing type uses the feed switcher.** All / Local / Subscribed (and Saved) are chosen from the feed switcher (`FeedSwitcherViewController`), which swaps the post list to the selected feed in place. The post list itself has no in-feed listing-type control — its feed is changed only by re-selecting from the switcher or by changing the sort. How the switcher is reached is size-class-dependent (see below).
- **Community-scoped feed.** Opening a community shows the community screen (header plus feed); the feed below the header is the same post list, scoped to that one community by name and instance. Its navigation title reads `community@instance`.
- **Sort menu.** Every feed carries a sort button (the `line.horizontal.3.decrease.circle` glyph) in the navigation bar. It is a single-selection menu; the active sort is checked. Changing the sort rebuilds the feed from the top under the new ordering.
- **Sort options.** The menu offers, as a top group: Active, Hot, New, Old, Controversial, Scaled. A nested "Top" submenu offers the time ranges below. A final group offers Most Comments and New Comments.
- **Top time ranges.** The Top submenu is single-selection and lists: Six Hours, Twelve Hours, Day, Week, Month, Three Months, Six Months, Nine Months, Year, All. (There is no "Top Hour" — the finest grain is six hours.)
- **Sort changes feel like a new feed.** Picking a sort builds a fresh feed with the same listing/community but the chosen sort, resets pagination to the head, and the list reloads from the server.
- **Undo an accidental scroll-to-top.** Tapping the status bar scrolls the feed to the top (the standard iOS gesture). When that happens from at least a screen deep it is often accidental, so a "Jumped to top" toast offers a one-tap **Undo** that snaps back to where you were (the restored row pulses); a second status-bar tap while the undo is armed toggles back too. Manually scrolling dismisses the hint, but the saved position survives: if you scroll partway back down and tap the status bar again, the undo still returns you to the deepest place you were, not the shallower spot you stopped at. The saved position resets once you use the undo or the feed changes.
- **Reaching the feed switcher is size-class-dependent.** On iPhone (compact width) the switcher sits beneath the post list in the navigation stack, so swiping in from the left edge (the system back gesture) reveals it. On iPad (regular width) the always-visible primary column must not be popped away, so the navigation title is a tappable control instead — the feed name with a trailing `chevron.down` — that presents the switcher as a popover anchored to it. Picking a feed (or "Browse all communities") dismisses the popover; the primary column is never replaced by the switcher.

## Scenarios

### The frontpage opens on your default listing

- **Given** I launch the app
- **When** the post list appears
- **Then** it shows a frontpage feed using my account's preferred listing type (All if none is set)
- **And** the navigation title reads "All", "Local", or "Subscribed" to match

### Switch to the Local listing on iPad

- **Surfaces:** `ipad`
- **Given** the Posts tab at regular width
- **When** I tap the feed-name title and choose Local from the popover
- **Then** the post list shows the Local frontpage feed
- **And** the navigation title reads "Local"
- **And** the primary column is not replaced by the switcher

### Open a community feed

- **Given** a community
- **When** I open it
- **Then** the community screen shows its header above a post list scoped to that community
- **And** the navigation title reads `name@instance`

### Sort a feed by New

- **Given** any feed
- **When** I open the sort menu and choose New
- **Then** the feed reloads ordered newest-first
- **And** New is shown checked in the menu

### Pick a Top time range

- **Given** any feed
- **When** I open the sort menu, open Top, and choose Week
- **Then** the feed reloads showing the top posts of the past week
- **And** the menu remembers Top → Week as the active selection

### Undo a re-jump after scrolling partway back

- **Given** I am a screen or more deep in a feed
- **When** I tap the status bar to jump to the top, ignore the toast, scroll partway back down, then tap the status bar again
- **Then** the undo offers to return me to my original deep position, not the shallower spot I stopped at

### Switch feeds on iPhone via left-edge swipe

- **Surfaces:** `iphone`
- **Given** I am on the post feed on iPhone
- **When** I swipe in from the left edge
- **Then** the feed (listing-type) switcher appears

## Not supported / out of scope

- No multi-feed view, combined feed, or feed tabs — one feed is shown at a time.
- "Moderator view" is a defined listing type but is not offered as a sidebar entry.
- The Saved feed is its own capability and is documented separately (it appears in the Subscriptions sidebar and reuses this same post list).
- Changing a feed's sort does not persist as the account default; the default sort is set in Settings, a separate feature.
