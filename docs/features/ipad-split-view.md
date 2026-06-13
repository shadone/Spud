# iPad split-view handoff

- **Surfaces:** `ipad`, `iphone`
- **Status:** shipped
- **Related:** [Subscriptions sidebar](subscriptions-sidebar.md), [Feeds and sorting](feeds-and-sorting.md), [Post detail and comments](post-detail-and-comments.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

The Posts tab is a two-column split view: a primary column holding the subscriptions sidebar with the post list on top of it, and a detail column holding the selected post. On a regular-width iPad the two columns sit side by side, so a tapped post opens in the detail pane while the list stays visible. When the layout narrows to compact width — an iPhone, or an iPad multitasking split, or a rotation that crosses the width boundary — the columns merge into one navigation stack with the open post pushed on top, and they split apart again when the layout widens back. The selected post survives that collapse and expand without being lost.

## Behavior and rules

- **Two-column split view.** The Posts tab is a `.doubleColumn` split view. The primary column is a navigation stack rooted at the subscriptions sidebar with the post list pushed on top; the detail column is a navigation stack rooted at the post detail pane. At regular width the split shows one column beside the secondary, tiled.
- **Only the Posts tab is split.** The app's other tabs — Account, Search, Inbox, Preferences — are plain navigation stacks. The split-view handoff applies to the Posts tab alone.
- **Empty detail placeholder.** When no post is selected at regular width, the detail pane shows a centered "No posts selected" placeholder. Selecting a post in the list replaces it with that post's detail.
- **Collapse carries the detail into the stack.** When the layout collapses to compact, any open post detail is moved from the detail column onto the end of the primary (now single) navigation stack, so the post you were reading stays on screen. The empty placeholder is filtered out during this move — only a real post is carried over.
- **Expand restores the detail column.** When the layout expands back to regular, the stack is split at its base (sidebar plus post list): the base stays in the primary column, and anything pushed above it — the post detail you had open — moves back into the detail column. If nothing was open, the empty placeholder is restored.
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
- **Then** the sidebar and post list stay in the primary column
- **And** the open post moves back into the detail pane

### A regular-to-regular rotation leaves both columns in place

- **Surfaces:** `ipad`
- **Given** a post open in the detail pane on a full-screen iPad
- **When** I rotate the device between portrait and landscape, both regular width
- **Then** both columns stay as they were and the open post is undisturbed

## Not supported / out of scope

- **No third column.** The split view is two columns; there is no separate persistent sidebar column. The subscriptions sidebar is the root beneath the post list in the primary stack, reachable by going back, not a standing column. See [Subscriptions sidebar](subscriptions-sidebar.md).
- **No multi-pane on iPhone.** On a compact iPhone the split view is always a single collapsed stack; there is no side-by-side layout.
- **Selection is not restored across launches.** The handoff preserves an open post across collapse and expand within a session; it is not a state-restoration feature that reopens the last post on a fresh launch.
