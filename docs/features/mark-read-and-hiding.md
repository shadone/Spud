# Marking posts read and hiding read posts

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Configurable swipe actions](swipe-actions.md), [NSFW content visibility](nsfw-content.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Keeps a feed focused on what you haven't seen yet. Posts can be marked read as you
interact with them — and optionally as they scroll past — and read posts can be hidden
from the feed, either the moment they're read or only when the feed next refreshes so
nothing disappears out from under your scroll. Every toggle lives in Settings → Post
Marking & Hiding and applies live.

## Behavior and rules

- **Mark Posts as Read.** The master toggle. Posts you interact with — opening or upvoting them — are marked read.
- **Mark as Read on Scrolling.** A sub-option, available only while Mark Posts as Read is on, that additionally marks posts read as they scroll out of view.
- **Hide Read Posts.** When on, a "When" picker chooses the hiding mode:
  - **Immediately** — a post leaves the feed the instant it is marked read.
  - **On Refresh** — only posts that were already read when the feed last refreshed are hidden; posts read during the current session stay until the next refresh, so nothing vanishes mid-scroll.
- **Hiding is a view filter, not a mutation.** The full ordered feed is produced once and never altered; the visible list is filtered down to what should currently show (`HideReadPostsFilter`). Read state, ordering, and pagination are untouched — turning hiding off restores the posts in place.
- **Everything applies live.** The post list observes the same preference streams, so toggling any of these reflects immediately without a relaunch.
- **The same settings screen also hosts the "Show NSFW Content" toggle.** That preference is a separate, server-side feed filter documented in [NSFW content visibility](nsfw-content.md); it is grouped here because it is another content-visibility control.

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
- **When** a post becomes read (opened, upvoted, or scrolled past)
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

## Not supported / out of scope

- Mark as Read on Scrolling is unavailable unless Mark Posts as Read is on (the toggle is disabled).
- Hiding never reorders or deletes posts from the underlying feed or pagination — it only filters the visible list.
- There is no bulk "mark this entire feed read" control. (The Inbox has its own mark-all-read; that is a separate feature.)
