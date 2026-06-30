# iPad split-view handoff

- **Surfaces:** `ipad`, `iphone`
- **Status:** shipped
- **Related:** [Subscriptions sidebar](subscriptions-sidebar.md), [Feeds and sorting](feeds-and-sorting.md), [Post detail and comments](post-detail-and-comments.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

The Posts tab is a two-column split view: a primary column holding the post list, and a detail column holding the selected post. On a regular-width iPad the two columns sit side by side, so a tapped post opens in the detail pane while the list stays visible. At regular width the primary column shows the post list alone — there is no feed switcher beneath it, so the always-visible primary column is never popped away; the feed is changed through a navbar-title popover instead. At compact width the feed switcher sits beneath the post list and is reached by a left-edge back-swipe. When the layout narrows to compact width — an iPhone, or an iPad multitasking split, or a rotation that crosses the width boundary — the columns merge into one navigation stack with the open post pushed on top, and they split apart again when the layout widens back. The selected post survives that collapse and expand without being lost.

## Behavior and rules

- **Two-column split view.** The Posts tab is a `.doubleColumn` split view. The detail column is a navigation stack rooted at the post detail pane. The primary column's base is size-class-dependent: at regular width it is the post list alone, and at compact width it is the feed switcher (`FeedSwitcherViewController`) with the post list pushed on top — the same `postListNavigationController` is reused for both, and the switcher is inserted on collapse / stripped on expand. At regular width the split shows one column beside the secondary, tiled. (The subscriptions list is not part of this stack — it is a separate Communities tab; see [Subscriptions sidebar](subscriptions-sidebar.md).)
- **Feed selection differs by width.** At regular width the feed name in the navigation bar is a tappable title control (`chevron.down`) that presents the feed switcher as a popover, so the persistent primary column is never replaced. At compact width the switcher sits beneath the post list and is revealed by the left-edge back-swipe. See [Feeds and sorting](feeds-and-sorting.md).
- **Only the Posts tab is split.** The app's other tabs — Account, Search, Inbox, Preferences — are plain navigation stacks. The split-view handoff applies to the Posts tab alone.
- **Empty detail placeholder.** When no post is selected at regular width, the detail pane shows a centered "No posts selected" placeholder. Selecting a post in the list replaces it with that post's detail.
- **Collapse carries the detail into the stack.** When the layout collapses to compact, the feed switcher is re-inserted at the base of the primary stack (if absent), and any open post detail is moved from the detail column onto the end of that (now single) navigation stack, so the post you were reading stays on screen. The empty placeholder is filtered out during this move — only a real post is carried over.
- **Expand restores the detail column.** When the layout expands back to regular, the feed switcher is stripped from the primary stack, leaving the post list as the base; anything pushed above it — the post detail you had open — moves back into the detail column. If nothing was open, the empty placeholder is restored.
- **A single post list survives every transition.** The post list is a retained instance that is only moved within or between the columns across collapse/expand — it is never recreated — so its feed observation and scroll position persist through the handoff.
- **Rotation falls out of the column behavior.** There is no separate rotation handling. A rotation that does not change the width class (for example an iPad turning between full-screen portrait and landscape, both regular) keeps both columns untouched. A rotation that does cross the compact boundary triggers the same collapse or expand handoff as any other width change.

## Scenarios

### A tapped post opens beside the list on iPad

- **Surfaces:** `ipad`
- **Given** the Posts tab at regular width with a feed in the list
- **When** I tap a post
- **Then** the post detail opens in the detail pane beside the list
- **And** the list stays visible in the primary column

### The detail pane shows a placeholder when nothing is selected

- **Surfaces:** `ipad`
- **Given** the Posts tab at regular width with no post selected
- **When** I look at the detail pane
- **Then** it shows a centered "No posts selected" placeholder

### The open post survives collapse to compact

- **Surfaces:** `ipad`, `iphone`
- **Given** a post open in the detail pane on a regular-width iPad
- **When** the layout narrows to compact (a multitasking split, or rotation across the width boundary)
- **Then** the columns merge into one navigation stack
- **And** the post I was reading is pushed on top of it, not lost

### The open post returns to the detail pane on expand

- **Surfaces:** `ipad`
- **Given** a post pushed on the single stack at compact width
- **When** the layout widens back to regular
- **Then** the post list stays in the primary column (the feed switcher is stripped from beneath it)
- **And** the open post moves back into the detail pane

### Feed selection on iPad does not pop the primary column

- **Surfaces:** `ipad`
- **Given** the Posts tab at regular width
- **When** I tap the feed-name title and pick a feed from the popover
- **Then** the post list updates to the chosen feed and its title updates
- **And** the primary column is never replaced by the feed switcher (no back-swipe reveals a switcher beneath it)

### A regular-to-regular rotation leaves both columns in place

- **Surfaces:** `ipad`
- **Given** a post open in the detail pane on a full-screen iPad
- **When** I rotate the device between portrait and landscape, both regular width
- **Then** both columns stay as they were and the open post is undisturbed

## Not supported / out of scope

- **No third column.** The split view is two columns; there is no separate persistent sidebar column. The feed switcher is reached by the navbar-title popover at regular width, or a left-edge back-swipe (beneath the post list) at compact width — it is not a standing column. The subscriptions list is a separate Communities tab. See [Feeds and sorting](feeds-and-sorting.md) and [Subscriptions sidebar](subscriptions-sidebar.md).
- **No multi-pane on iPhone.** On a compact iPhone the split view is always a single collapsed stack; there is no side-by-side layout.
- **Selection is not restored across launches.** The handoff preserves an open post across collapse and expand within a session; it is not a state-restoration feature that reopens the last post on a fresh launch.
