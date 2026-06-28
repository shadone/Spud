# Default sort

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped — both the default post sort and the default comment sort persist across launches
- **Related:** [feeds-and-sorting.md](feeds-and-sorting.md), [post-detail-and-comments.md](post-detail-and-comments.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Settings → General has a Posts default-sort picker and a Comments default-sort picker. The default post sort is the sort new feeds open with; the default comment sort is the order new comment threads load in. Both choices are remembered across launches: the comment default is stored in the local preferences store, and the post default is persisted per account (it is a per-account value, not a global preference).

## Behavior and rules

- **Default post sort seeds new feeds.** When a feed (frontpage, community, profile, subscriptions) is built, it opens at the account's default post sort. The value comes from the account record's `default_sort_type`, falling back to Hot when none is set.
- **Default comment sort seeds new threads.** When a post's comment tree loads, it uses the stored global default comment sort (default Hot).
- **Per-post comment sort.** The post-detail screen has a config control (the `slider.horizontal.3` toolbar button) that opens a popover with a Sort picker — Hot, Top, New, Old, Controversial. Choosing one re-sorts the open post's comments immediately. This is a per-post override for that session only; it does not change the global default comment sort in Settings. See [post-detail-and-comments.md](post-detail-and-comments.md).
- **The post picker is persisted per account.** Changing the Posts default-sort picker writes the new value back to the account record's `default_sort_type` column, so it survives relaunch. Because the default post sort is a per-account value (each account can carry its own server-synced sort), it is stored on the account, not in the global preferences store the comment picker uses.
- **Per-feed sort still overrides at the feed.** The default sort is the starting point; changing a feed's sort in the feed itself is a separate, per-feed action documented in [feeds-and-sorting.md](feeds-and-sorting.md). The default does not retroactively re-sort feeds already open.

## Scenarios

### New feeds open at the default post sort

- **Given** my account's default post sort is Hot
- **When** I open a community or frontpage feed
- **Then** it loads sorted by Hot
- **And** I can still change that feed's sort from within the feed

### Set the default post sort

- **Given** Settings → General with the Posts default on Hot
- **When** I select New
- **Then** the choice is saved to my account
- **And** it is still New after I relaunch the app
- **And** newly opened feeds load sorted by New

### Set the default comment sort

- **Given** Settings → General with the Comments default on Hot
- **When** I select Top
- **Then** the choice is stored
- **And** newly opened comment threads load sorted by Top

### Per-post comment sort in the thread

- **Given** an open post with its comment tree
- **When** I tap the config (slider) button and pick a sort
- **Then** that post's comments re-sort immediately
- **And** the global default comment sort in Settings is unchanged

## Not supported / out of scope

- **The Posts default-sort change is stored locally, not pushed to the server.** Selecting a post sort here persists to the local account record so it survives relaunch, but it is not mirrored to the instance via `save_user_settings`; a fresh sign-in on another device sees the server's value until that round-trip is wired.
- Changing the default does not re-sort feeds or threads that are already open (the per-post picker re-sorts only the current post).
- No per-community or per-feed default-sort overrides; per-feed sort changes belong to [feeds-and-sorting.md](feeds-and-sorting.md).
