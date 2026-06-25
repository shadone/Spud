# NSFW content visibility

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [feeds-and-sorting.md](feeds-and-sorting.md), [mark-read-and-hiding.md](mark-read-and-hiding.md), [discover.md](discover.md), [new-post.md](new-post.md)

## What it does

Controls whether posts and communities marked not-safe-for-work appear in feeds and the
community directory. The default is to hide NSFW content. A single client preference governs
it everywhere — the frontpage, community, and saved feeds, the Quick Switch popover, and the
Discover directory all read the same setting — and for a signed-in account the choice is also
pushed to the server so it sticks across devices.

## Behavior and rules

- **Hidden by default.** Out of the box NSFW posts and communities are filtered out. The preference defaults to off (hide).
- **Filtering is server-side.** Each feed fetch sends the preference as the `show_nsfw` request parameter to the server's post listing, so the server omits NSFW posts entirely. This works for signed-out accounts too — it does not depend on any account setting.
- **Two places to toggle it.** Settings → Post Marking & Hiding has a "Show NSFW Content" toggle with an explanatory footer; the Quick Switch popover (the `slider.horizontal.3` control in the feed toolbar) has a "Show NSFW" toggle for changing it without leaving the feed.
- **Changing it reloads the open feed.** Because the filter is applied by the server at fetch time, flipping the toggle re-fetches the current feed from the top under the new setting rather than filtering in place.
- **Read at fetch time.** The current preference is read on every page fetch, so a change is honoured on the next page or reload.
- **Synced to the server when signed in.** For a signed-in account, changing the preference also writes `show_nsfw` to the account's server-side user settings (best-effort) and mirrors the new value onto the locally cached account row. To avoid duplicate writes from the several post lists that observe the change, only the frontpage feed performs this sync; community and saved feeds reload but do not sync. A signed-out account skips the server write — the local preference still filters its feeds.
- **Discover agrees with the feeds.** The Discover community directory reads the same client preference: when off, NSFW communities are filtered out of the directory and network search results; when on, they appear (badged). Curated rails (starter packs, trending) stay clean regardless.

## Scenarios

### NSFW posts are hidden by default

- **Given** a fresh install with the preference untouched
- **When** I browse any feed
- **Then** posts marked NSFW are not shown

### Show NSFW from Settings

- **Given** Settings → Post Marking & Hiding with Show NSFW Content off
- **When** I turn it on
- **Then** the open feed reloads from the top and now includes NSFW posts
- **And** if I am signed in, the change is pushed to my server-side user settings

### Toggle NSFW from the feed

- **Given** the Quick Switch popover open over a feed
- **When** I turn Show NSFW on
- **Then** the feed reloads to include NSFW posts without going to Settings

### Signed-out filtering still works

- **Given** a signed-out (browsing) account with Show NSFW off
- **When** I load a feed
- **Then** NSFW posts are filtered out by the server via the request parameter
- **And** no account setting is read or written

### Discover follows the same setting

- **Given** Show NSFW is off
- **When** I open Discover
- **Then** NSFW communities are absent from the directory and from network search results

## Not supported / out of scope

- There is no separate "blur NSFW" mode — content is either shown or hidden, not blurred.
- The Home Screen widget always hides NSFW (it has no access to the in-app preference).
- The preference is global; there is no per-community or per-feed NSFW override.
- Marking your own new post NSFW is a separate control on the post composer (see new-post.md), independent of this visibility preference.
