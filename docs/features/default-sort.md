# Default sort

- **Surfaces:** `iphone`, `ipad`
- **Status:** partial — the default comment sort is persisted; the default post sort picker is not yet persisted (it resets on relaunch)
- **Related:** [feeds-and-sorting.md](feeds-and-sorting.md), [post-detail-and-comments.md](post-detail-and-comments.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Settings → General has a Posts default-sort picker and a Comments default-sort picker. The default post sort is the sort new feeds open with; the default comment sort is the order new comment threads load in. The comment default is stored locally and remembered across launches. The post default is currently a session-only choice in this screen — it is not yet written back, so it reverts to the account's value on relaunch (see Not supported).

## Behavior and rules

- **Default post sort seeds new feeds.** When a feed (frontpage, community, profile, subscriptions) is built, it opens at the account's default post sort. The value comes from the account record's server-synced `default_sort_type`, falling back to Hot when none is set.
- **Default comment sort seeds new threads.** When a post's comment tree loads, it uses the stored default comment sort (default Hot). This is a preference only — the post-detail screen has no in-screen comment-sort picker, consistent with [post-detail-and-comments.md](post-detail-and-comments.md).
- **The post picker is not persisted yet.** Changing the Posts default-sort picker updates only the in-memory settings state; it is not saved (a `save_user_settings` write is still to be wired). On relaunch it shows the account's value again. The comment picker, by contrast, is persisted through the preferences store.
- **Per-feed sort still overrides at the feed.** The default sort is the starting point; changing a feed's sort in the feed itself is a separate, per-feed action documented in [feeds-and-sorting.md](feeds-and-sorting.md). The default does not retroactively re-sort feeds already open.

## Scenarios

### New feeds open at the default post sort

- **Given** my account's default post sort is Hot
- **When** I open a community or frontpage feed
- **Then** it loads sorted by Hot
- **And** I can still change that feed's sort from within the feed

### Set the default comment sort

- **Given** Settings → General with the Comments default on Hot
- **When** I select Top
- **Then** the choice is stored
- **And** newly opened comment threads load sorted by Top

### Comment sort is preference-only in the thread

- **Given** an open post with its comment tree
- **When** I look for a sort control in the post-detail screen
- **Then** there is none — the comment order follows the stored default comment sort

## Not supported / out of scope

- **The Posts default-sort picker is not yet persisted.** Selecting a post sort here updates the current session only; it is not saved to the server or locally, so it reverts to the account value on the next launch. Tracked for a future `save_user_settings` write.
- No in-screen comment-sort picker — comment order is set only through the default comment sort preference.
- Changing the default does not re-sort feeds or threads that are already open.
- No per-community or per-feed default-sort overrides; per-feed sort changes belong to [feeds-and-sorting.md](feeds-and-sorting.md).
