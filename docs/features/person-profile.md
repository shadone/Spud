# Person / user profile

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Community screen](community-screen.md), [Search](search.md), [Post detail and comments](post-detail-and-comments.md), [Feeds and sorting](feeds-and-sorting.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

The person profile pins a header above a segmented Posts / Comments list of that user's own content. The header shows an optional banner, an overlapping circular avatar, the display name, the canonical `@name@instance` handle, a stats line (post count, comment count, and cake day), and a rendered markdown bio. The segmented control switches between the user's posts (feed-style rows) and comments (comment-with-context rows); tapping a post opens it in Post detail, and tapping a comment opens its post. The screen is reached from a user search result or a user mention link and works on iPhone and iPad.

## Behavior and rules

- **Header above segmented content.** The header is pinned; a Posts / Comments segmented control sits below it, and the selected tab's list fills the rest.
- **Header is database-driven.** Header fields come from the local database's person-profile observation, so the avatar, banner, handle, stats, and bio update live as the record changes.
- **Content is a fetched snapshot.** The posts and comments are fetched one page at a time for the profile (at the account default sort) and held in memory — a snapshot of the requested page, like search results, not a persistent paging feed. The two lists are decoded from a single response and the segmented control switches between them.
- **Resolve-then-show.** Opening a profile first fetches the person's info behind a "Loading…" spinner; once the local row appears the header-plus-content screen is shown.
- **Pull to refresh.** The content list has pull-to-refresh, which re-fetches the active tab.
- **Designed states.** Each tab shows a spinner while loading, an empty state ("No posts" / "No comments") when that tab is empty, and an error state with a pull-to-refresh hint on failure.
- **Message and block, signed in only.** When signed in and viewing someone else's profile, a Message button opens a private-message composer to that user, and an overflow menu offers Block / Unblock user. These are suppressed on your own profile and when signed out. The block state is resolved from the server's block list on appear; blocking asks for confirmation.
- **Copy handle.** Long-pressing the header offers Copy handle (the `@name@instance` string), plus Block / Unblock when not your own profile.
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
