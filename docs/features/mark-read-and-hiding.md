# Marking posts read and hiding read posts

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Configurable swipe actions](swipe-actions.md), [NSFW content visibility](nsfw-content.md), [Removed and unavailable posts](removed-unavailable-content.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Keeps a feed focused on what you haven't seen yet. Posts can be marked read as you
interact with them — and optionally as they scroll past — and read posts can be hidden
from the feed, either the moment they're read or only when the feed next refreshes so
nothing disappears out from under your scroll. Every toggle lives in Settings → Post
Marking & Hiding and applies live. The two most reached-for controls — Hide Read Posts
and Mark as Read on Scroll — are also in the feed's Quick Switch (config) popover, so you
can flip them without leaving the feed.

## Behavior and rules

- **Mark Posts as Read.** The master toggle. Posts are marked read when (a) you open the post detail (when the mark-on-open preference is on), (b) it scrolls off-screen (when the mark-on-scroll preference is on), or (c) you open media (image/video) directly from the feed cell.
- **Mark as Read on Scrolling.** A sub-option, available only while Mark Posts as Read is on, that additionally marks posts read as they scroll out of view.
- **Hide Read Posts.** When on, a "When" picker chooses the hiding mode:
  - **Immediately** — a post leaves the feed the instant it is marked read.
  - **On Refresh** — only posts that were already read when the feed last refreshed are hidden; posts read during the current session stay until the next refresh, so nothing vanishes mid-scroll.
- **Hiding is a view filter, not a mutation.** The full ordered feed is produced once and never altered; the visible list is filtered down to what should currently show (`HideReadPostsFilter`). Read state, ordering, and pagination are untouched — turning hiding off restores the posts in place. Posts that are gone from the server are not automatically hidden by this filter; they remain in the feed with a neutral badge — see [Removed and unavailable posts](removed-unavailable-content.md).
- **Everything applies live.** The post list observes the same preference streams, so toggling any of these reflects immediately without a relaunch.
- **Quick access from the feed.** The feed's Quick Switch (config) popover — the `slider.horizontal.3` toolbar button — has a "Read Posts" section with Hide Read Posts (and its Immediately / On Refresh "When" picker) plus a single Mark as Read on Scroll toggle. That one toggle reflects whether scroll-marking is actually in effect, which requires the master Mark Posts as Read: turning it on also turns Mark Posts as Read on (so it is never a no-op), and turning it off leaves marking-on-open intact. The finer master/sub-option split stays in Settings. Both surfaces write the same global preferences and apply live.
- **The same settings screen also hosts the "Show NSFW Content" toggle.** That preference is a separate, server-side feed filter documented in [NSFW content visibility](nsfw-content.md); it is grouped here because it is another content-visibility control.
- **Instance capability gate.** When the signed-in account's home instance is on Lemmy 1.0, marking a post read still applies and displays locally exactly as above, but the server-side read-state sync silently no-ops (no error, no UI change); separately, the post-list "Hide" context-menu action — an explicit per-post server hide, distinct from this feature's auto-hide-on-read filter — shows an explanatory action sheet instead of hiding the post. See [Instance capability gating](instance-capability-gating.md).

## Scenarios

### Opening a post marks it read

- **Given** Mark Posts as Read is on
- **When** I open a post and return to the feed
- **Then** that post is shown as read

### Scrolling marks posts read

- **Given** Mark Posts as Read and Mark as Read on Scrolling are both on
- **When** a post scrolls out of view
- **Then** it is marked read

### Hide read immediately

- **Given** Hide Read Posts is on, mode Immediately
- **When** a post becomes read (opened, media opened, or scrolled past)
- **Then** it disappears from the feed right away

### Hide read on refresh keeps your place

- **Given** Hide Read Posts is on, mode On Refresh
- **When** I read several posts while scrolling
- **Then** they stay in place as I scroll
- **And** they are removed only when the feed next refreshes

### Turning hiding off restores posts

- **Given** Hide Read Posts is on and some read posts are hidden
- **When** I turn Hide Read Posts off
- **Then** the read posts reappear in the feed, in their original order

### Turn on scroll marking from the feed popover

- **Given** Mark Posts as Read is off
- **When** I open the feed's Quick Switch popover and turn on Mark as Read on Scroll
- **Then** Mark Posts as Read turns on as well
- **And** posts are marked read as they scroll out of view

## Not supported / out of scope

- In Settings, Mark as Read on Scrolling is a disabled sub-toggle unless Mark Posts as Read is on. The Quick Switch popover instead auto-enables Mark Posts as Read when you turn scroll marking on, so its toggle is never disabled.
- Hiding never reorders or deletes posts from the underlying feed or pagination — it only filters the visible list.
- There is no bulk "mark this entire feed read" control. (The Inbox has its own mark-all-read; that is a separate feature.)
