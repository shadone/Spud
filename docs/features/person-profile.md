# Person / user profile

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Community screen](community-screen.md), [Search](search.md), [Post detail and comments](post-detail-and-comments.md), [Feeds and sorting](feeds-and-sorting.md), [Sharing](sharing.md), [Moderation actions](moderation-actions.md), [Private messages](private-messages.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

The person profile shows a header above a segmented Posts / Comments list of that user's own content. The header shows an optional banner, an overlapping circular avatar, the display name, the canonical `@name@instance` handle (the user's own home instance, even for a remote user viewed from another account), a stats line (post count, comment count, and cake day), and a rendered markdown bio. The segmented control switches between the user's posts (feed-style rows) and comments (comment-with-context rows); tapping a post opens it in Post detail, and tapping a comment opens its post. Account status the server reports — a ban, a deleted account, a bot or admin account, a Matrix contact — surfaces in the header. The navigation bar carries a sort button and a `···` overflow menu (sharing, plus Message / Block when signed in). The screen is reached from a user search result or a user mention link and works on iPhone and iPad.

## Behavior and rules

- **Header scrolls with the content.** The header and the Posts / Comments segmented control are hosted inside the list as its scrolling header, so a long bio scrolls away with the content instead of overflowing a fixed region at the top. The selected tab's list fills the rest below.
- **Own-instance handle.** The `@name@instance` handle uses the person's own home instance (derived from their federated `actorId`), not the viewing account's home instance — so a remote user reads e.g. `@ddenis@lemmy.world`, not `@ddenis@<your-instance>`.
- **Account status.** A banned account shows a prominent warning banner at the top of the header, with the expiry date for a temporary ban (a permanent ban reads simply "Banned"). A self-deleted account shows an "Account deleted" banner; a ban takes precedence when both apply. Bot and Admin accounts get a small pill badge beside the display name. When the user has set a Matrix contact, it shows as a copyable row under the stats. All of this is sourced from the person record; the ban reflects the queried instance's federated view (admin status is known only once the full profile has loaded). Everything is hidden when not applicable, so a normal account looks unchanged.
- **Header is database-driven.** Header fields come from the local database's person-profile observation, so the avatar, banner, handle, stats, and bio update live as the record changes.
- **Content is a fetched snapshot.** The posts and comments are fetched one page at a time for the profile (at the active sort — the account default initially, changeable from the navbar sort button) and held in memory — a snapshot of the requested page, like search results, not a persistent paging feed. The two lists are decoded from a single response and the segmented control switches between them.
- **Resolve-then-show.** Opening a profile first fetches the person's info behind a "Loading…" spinner; once the local row appears the header-plus-content screen is shown.
- **Pull to refresh.** The content list has pull-to-refresh, which re-fetches the active tab.
- **Designed states.** Each tab shows a spinner while loading, an empty state ("No posts" / "No comments") when that tab is empty, and an error state with a pull-to-refresh hint on failure.
- **Sort.** A navigation-bar sort button reorders the profile. A single fetch returns both Posts and Comments, so one sort applies to the whole screen; it offers exactly the set the API accepts (Active / Hot / New / Old / Controversial / Scaled / Top 6h–All / Most Comments / New Comments), grouped like the Community sort. Per-screen only — it does not change the account default.
- **Overflow menu.** A navigation-bar `···` menu groups sharing — Copy handle, Copy Link, Share…, and Open in Browser (the link / share / browser actions need the resolved profile URL, so they appear once it loads) — and, when signed in and viewing someone else's profile, Message and Block / Unblock. The sharing group is always available; Message / Block are evaluated each time the menu opens, so Block / Unblock reflects live state. Blocking asks for confirmation, and the block state is resolved from the server's block list on appear.
- **Copy handle.** Long-pressing the header also offers Copy handle (the `@name@instance` string), plus Block / Unblock when not your own profile — the same actions available in the overflow menu.
- **Bio links.** Links in the bio open inline: a person link opens another Person profile, a community link opens the [Community screen](community-screen.md), and other links open externally.

## Scenarios

### Open a profile shows header and posts

- **Given** a user I tapped from a search result or a mention
- **When** the profile resolves
- **Then** a header with avatar, display name, `@name@instance` handle, stats, and bio appears above the user's Posts list

### Switch to the Comments tab

- **Given** an open profile on the Posts tab
- **When** I tap Comments
- **Then** the list shows the user's comments as comment-with-context rows

### Tap a post or comment

- **Given** the Posts or Comments list
- **When** I tap a row
- **Then** a post opens in Post detail and a comment opens the post it belongs to

### Pull to refresh re-fetches the tab

- **Given** an open profile
- **When** I pull the list down
- **Then** the active tab's content is re-fetched

### An empty tab shows a placeholder

- **Given** a user with no comments
- **When** I open the Comments tab
- **Then** a "No comments" empty state is shown

### Message and block on someone else's profile

- **Given** I am signed in and viewing another user's profile
- **When** I look at the navigation bar
- **Then** a Message button and an overflow Block / Unblock menu are available
- **And** on my own profile those actions are not shown

## Not supported / out of scope

- The posts / comments lists are a single fetched page — there is no infinite scroll or pagination on a profile.
- The profile content sort follows the account default; there is no in-screen sort picker.
- Subscribing to a user is not a concept; the profile actions are Message and Block / Unblock only.
- No follower / following lists, no profile editing, and no moderator-level actions on the user.
