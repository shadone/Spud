# NSFW content visibility and blur

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [feeds-and-sorting.md](feeds-and-sorting.md), [mark-read-and-hiding.md](mark-read-and-hiding.md), [discover.md](discover.md), [new-post.md](new-post.md), [post-thumbnails.md](post-thumbnails.md), [community-screen.md](community-screen.md), [search.md](search.md)

## What it does

Controls whether posts and communities marked not-safe-for-work appear in feeds and the
community directory, and whether NSFW media is obscured until tapped. Two independent
preferences govern the experience:

- **Show NSFW** — whether NSFW content appears at all. Filtering is server-side for feeds
  (the `show_nsfw` request parameter) and client-side for discovery surfaces. Default off.
- **Blur NSFW** — when NSFW content is shown, whether its media is covered by a frosted-glass
  overlay until tapped. Default on.

Both preferences are surfaced in Settings → Post Marking & Hiding and in the Quick Switch
popover. (Settings uses the labels "Show NSFW Content" and "Blur NSFW Content"; the Quick
Switch popover uses the shorter "Show NSFW" and "Blur NSFW".) For a signed-in account both choices are also pushed to the server so they stick
across devices.

## Behavior and rules

### Show NSFW

- **Hidden by default.** Out of the box NSFW posts and communities are filtered out. The
  preference defaults to off (hide).
- **Filtering is server-side for feeds.** Each feed fetch sends the preference as the
  `show_nsfw` request parameter so the server omits NSFW posts entirely. This works for
  signed-out accounts too — it does not depend on any account setting.
- **Two places to toggle it.** Settings → Post Marking & Hiding has a "Show NSFW Content"
  toggle with an explanatory footer; the Quick Switch popover (the `slider.horizontal.3`
  control in the feed toolbar) has a "Show NSFW" toggle for changing it without leaving the
  feed.
- **Changing it reloads the open feed.** Because the filter is applied by the server at fetch
  time, flipping the toggle re-fetches the current feed from the top under the new setting
  rather than filtering in place.
- **Read at fetch time.** The current preference is read on every page fetch, so a change is
  honoured on the next page or reload.
- **Synced to the server when signed in.** For a signed-in account, changing the preference
  also writes `show_nsfw` to the account's server-side user settings (best-effort) and mirrors
  the new value onto the locally cached account row. To avoid duplicate writes from the several
  post lists that observe the change, only the frontpage feed performs this sync; community and
  saved feeds reload but do not sync. A signed-out account skips the server write — the local
  preference still filters its feeds.
- **Age acknowledgment on first enable.** The very first time Show NSFW is turned on (from
  either Settings or Quick Switch) a confirmation alert appears: "Show adult content? By
  continuing you confirm you are of legal age to view adult material." Confirming enables Show
  NSFW; cancelling reverts the toggle. Subsequent toggles — including turning Show NSFW back on
  after it was turned off — skip the alert entirely. Turning Show NSFW off never prompts.
- **Discovery gating: feeds, Discover, Search, and the community picker.** When Show NSFW is
  off, NSFW content is filtered across all discovery surfaces: the server filters it from feeds;
  the Discover directory and its network search drop NSFW communities client-side; the global
  Search scene drops NSFW communities and posts from its results client-side; and the community
  picker in the post composer drops NSFW communities from its search results client-side.
  Already-subscribed communities and deep links are unaffected — gating is about discovery, not
  access.

### Blur NSFW

- **Independent of Show NSFW.** Blur and show/hide are separate axes. Enabling blur does not
  change which content is fetched; it only changes whether shown NSFW media is obscured.
- **Blur toggle is disabled when Show NSFW is off.** Because blur has no visible effect when
  NSFW is hidden, the "Blur NSFW" toggle in both Settings and Quick Switch is greyed out and
  accompanied by a short footnote ("Only applies when NSFW content is shown") whenever Show NSFW
  is off.
- **On by default.** The blur preference defaults to on, matching Lemmy's `blur_nsfw` default
  and the safe-by-default posture the platform expects of a UGC app.
- **Synced to the server when signed in.** Changing the blur preference writes `blur_nsfw` to
  the account's server-side user settings (frontpage-only sync, mirroring Show NSFW). A
  signed-out account skips the server write.
- **Toggling blur is a pure re-render, not a refetch.** Unlike Show NSFW, flipping blur does
  not re-fetch; it only re-applies or removes the overlay on visible items.
- **Where blur applies:**
  - **Post-list thumbnails.** NSFW post thumbnails are covered by a frosted-glass overlay.
    Tapping the overlay reveals that post's thumbnail for the rest of the session (reveal state
    is in-memory; resets on relaunch). Revealing the thumbnail does not open the post; a second
    tap (or tapping the cell body) opens as normal. A post is considered NSFW when either the
    post's own NSFW flag or its community's NSFW flag is set.
  - **Post-detail header image.** The lead image in the post detail header is blurred with the
    same frosted-glass overlay when the post is NSFW and blur is on. Tapping reveals it while
    viewing that post; the reveal resets when a different post is loaded (relevant on iPad where
    the detail column is reused across navigations).
  - **Community art (icons and banners).** NSFW community icons in Discover and the community
    banner on the community screen are blurred when shown and blur is on. Community art does not
    support tap-to-reveal in v1 — it remains blurred for the duration of the session while
    the community is NSFW and blur is on.
- **Discover agrees with the feeds.** The Discover community directory reads the same client
  preference: when Show NSFW is off, NSFW communities are filtered out of the directory and
  network search results; when on, they appear (badged with an "NSFW" pill). See
  [discover.md](discover.md).
- **NSFW badge on community header.** When a community is marked NSFW, its header on the
  community screen shows an "NSFW" badge regardless of blur state.

## Scenarios

### NSFW posts are hidden by default

- **Given** a fresh install with the preference untouched
- **When** I browse any feed
- **Then** posts marked NSFW are not shown

### Age acknowledgment on first-time enable

- **Given** Show NSFW has never been enabled on this device
- **When** I turn on Show NSFW from Settings or Quick Switch
- **Then** a confirmation alert appears asking me to confirm I am of legal age
- **And** confirming enables Show NSFW; cancelling leaves it off

### Subsequent Show NSFW toggles skip the alert

- **Given** Show NSFW has previously been acknowledged and enabled at least once
- **When** I turn Show NSFW on again after turning it off
- **Then** the feed reloads with NSFW content immediately, with no alert

### Show NSFW from Settings

- **Given** Settings → Post Marking & Hiding with Show NSFW Content off
- **When** I turn it on (and confirm the age acknowledgment if prompted)
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

### Blur NSFW thumbnails in the feed

- **Given** Show NSFW is on and Blur NSFW is on
- **When** I browse a feed containing NSFW posts
- **Then** NSFW posts appear in the list but their thumbnails are covered by a frosted-glass overlay
- **And** tapping the overlay on a post reveals that post's thumbnail for the rest of the session

### Blur the post-detail header image

- **Given** Show NSFW is on and Blur NSFW is on
- **When** I open an NSFW post's detail screen
- **Then** the lead header image is covered by the frosted-glass overlay
- **And** tapping the overlay reveals the image while viewing that post; navigating to a different post resets the reveal

### Community art is blurred in Discover and on the community screen

- **Given** Show NSFW is on and Blur NSFW is on
- **When** I view an NSFW community's icon in Discover or its banner on the community screen
- **Then** the icon/banner is covered by the frosted-glass overlay and remains blurred
- **And** the community screen header shows an "NSFW" badge

### Blur toggle is disabled when Show NSFW is off

- **Given** Show NSFW is off
- **When** I open Settings → Post Marking & Hiding or the Quick Switch popover
- **Then** the "Blur NSFW" toggle is greyed out with a note that it only applies when NSFW content is shown

### Toggling blur re-renders in place without refetching

- **Given** Show NSFW is on and I have a feed open
- **When** I flip the Blur NSFW toggle in Quick Switch or Settings
- **Then** the overlay appears or disappears on visible NSFW items without the feed reloading

### Search drops NSFW results when Show NSFW is off

- **Given** Show NSFW is off and I am on the Search tab
- **When** I search for communities or posts
- **Then** NSFW results are filtered from the list client-side

### Community picker drops NSFW communities when Show NSFW is off

- **Given** Show NSFW is off and I am composing a new post
- **When** I open the community picker and search
- **Then** NSFW communities do not appear in the picker results

### Discover follows the same setting

- **Given** Show NSFW is off
- **When** I open Discover
- **Then** NSFW communities are absent from the directory and from network search results

## Not supported / out of scope

- Community art (icons and banners) does not support tap-to-reveal; it remains blurred for the
  session while the community is NSFW and blur is on.
- Inline body images, comment images, and gallery images are not blurred (scope is thumbnails,
  post-detail header, and community art only).
- The Home Screen widget always hides NSFW (it has no access to the in-app preference); blur
  never applies to the widget.
- The preference is global; there is no per-community or per-feed NSFW override.
- Marking your own new post NSFW is a separate control on the post composer (see
  [new-post.md](new-post.md)), independent of this visibility preference.
- The registration flow does not set `blur_nsfw`; only post-login user settings sync covers it.
