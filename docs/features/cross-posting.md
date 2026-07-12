# Cross-posting

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [New post](new-post.md), [Draft persistence](draft-persistence.md), [Community screen](community-screen.md), [Display density and text size](display-density-and-text.md), [Marking posts read and hiding read posts](mark-read-and-hiding.md)

## What it does

Three complementary parts. **Creating** a cross-post: re-share an existing post into
another community. A "Cross-post" action on the feed's long-press menu and on the open
post's "•••" overflow menu opens the ordinary new-post composer, pre-filled with the
source post's title and link (and, when the full post is available, an attribution
quoting its body), with the target community left for the user to choose. From there it
behaves exactly like composing a brand-new post. **Viewing** a post's existing
cross-posts: when a post's server response reports other posts sharing its link, the
open post shows a "Cross-posted to N communities" section listing each one, tappable to
open it. **Grouping** duplicates in the feed: when the same link is posted to more than
one community and more than one of those posts is loaded into the feed at once, they
collapse into a single row with an "Also in ..." affordance and a context-menu jump to
each collapsed sibling — preference-gated, default on.

## Behavior and rules

- **Same composer, seeded content.** Cross-posting opens the standard new-post composer
  (see [New post](new-post.md)) with the title and link pre-filled and no target
  community chosen — it is a new post, not an edit, so the user picks where it goes.
- **Attribution when the body is available.** When the source post's full body is loaded
  (post detail), the composer's body is seeded with `cross-posted from: <original post's
  link>` followed by the body quoted line-by-line. Because that seeded text is ordinary
  markdown, once the cross-post is submitted its rendered body shows the original post's
  link as a normal tappable link, the same as any other post link.
- **No body available: title + link only.** Cross-posting from the feed (which doesn't
  carry the source post's full body) and cross-posting a link/no-body post both leave the
  composer's body empty — the pre-filled title and link alone establish the cross-post.
- **Freshly seeded content always wins.** If a stale, unsent draft happens to exist for
  "new post, no community chosen yet" (the same slot a plain new post would use), opening
  a cross-post does not get overwritten by it — the seeded title/link/body from the
  source post is what appears.
- **Requires sign-in.** Cross-posting creates a post, so it is gated the same way the
  ordinary compose entry points are: a signed-out account sees a "Sign in to post" alert
  instead of the composer.

### Cross-posts on a post

- **Data already fetched, now persisted.** Opening a post fetches its detail from the
  server, which reports the other posts that share its link (if any) alongside it. The
  client already fetched this to keep those posts' vote/comment counters fresh; it is now
  also persisted as a relationship (not just refreshed counters), so the open post can
  list them.
- **Server order, not re-sorted.** The section lists cross-posts in the order the server
  reported them, not by score or recency.
- **Replaces on every fetch.** Each time the post's detail is re-fetched (opening it fresh,
  or pull-to-refresh), the set of listed cross-posts is replaced wholesale to match the
  latest server response — a cross-post that no longer appears (e.g. deleted, or the link
  was edited) drops out; a newly-discovered one appears.
- **No section when there are none.** A post fetched with no cross-posts, or never
  fetched with the full post-detail request (e.g. opened straight from an already-cached
  feed row, before any pull-to-refresh), shows no section at all — nothing is forced to
  fetch it.
- **Each entry shows the community and a light metadata line.** A cross-post's row shows
  its community as `c/name@instance` plus a compact score/comment-count line; tapping it
  opens that post in-app (resolving it federated, so a cross-post hosted on a different
  instance opens correctly too), pushing on iPhone and opening in the detail column on
  iPad, like any other in-app post link.

### Grouping cross-posts in the feed

The same link is often posted to several communities. When more than one of those posts
lands in the same loaded feed page (or pages), the feed collapses them into one row so
scrolling isn't cluttered by duplicates of the same link.

- **Preference-gated, default on.** "Group Cross-posts" in Settings → Display (default
  on). Turning it off restores every collapsed row immediately, live — no relaunch or
  feed reload.
- **Grouped by link, not by post.** Rows are grouped when their `url` (the post's
  external link — Lemmy's own definition of a cross-post, which itself uses exact-url
  matching) matches after a conservative normalization: the host is lowercased and a
  single trailing slash is stripped from the path. The fragment (`#...`) and the query
  string are always kept as-is, even though that means two links differing only by a
  same-page anchor or a tracking parameter stay ungrouped — when unsure whether two links
  are "the same," the feed prefers to show both rather than risk merging two different
  posts (a hash-routed single-page app's `#/x` vs `#/y` are genuinely different pages, not
  the same page with a different anchor). Text posts and posts with no link never group;
  each always shows as its own row.
- **First-seen row is the primary.** Within the feed's current order, the first row for a
  given link keeps its position and becomes the primary; every later row for the same
  link is removed from the visible list and becomes one of its collapsed siblings.
- **"Also in ..." affordance on the primary.** The primary's cell shows a quiet metadata
  line naming the communities it's also posted to: "Also in c/community" for one sibling,
  "Also in c/a, c/b" for two, or "Also in N communities" for three or more. Informational
  only — it doesn't open anything by itself.
- **Jump to a sibling from the context menu.** Long-pressing the primary's cell adds an
  "Also posted in" submenu listing each collapsed sibling as `c/community@instance`;
  tapping one opens that post in-app, exactly like tapping any other post.
- **Same-page limitation, stated plainly.** The feed API returns no cross-post list
  alongside a page of posts, so grouping can only see what's actually loaded — it
  recomputes over the full loaded set on every feed update, so a duplicate that arrives
  on a later page still joins its earlier primary's group once loaded, but two
  duplicates that never land in the same session's loaded pages are never grouped. This
  is a documented limitation of client-side, same-page grouping, not a bug.
- **Runs after the hide-read filter.** A read post that's hidden by the "Hide Read Posts"
  preference is removed before grouping runs, so it can never anchor a group as the
  primary and is never counted as a collapsed sibling.
- **Independent of "Cross-posts on a post."** This groups rows already loaded in the
  *feed*; it has no bearing on the "Cross-posted to N communities" section on an *open*
  post (above), which is a one-shot server read of a single post's siblings, not a
  client-side same-page grouping.

## Scenarios

### Cross-post from the feed

- **Given** a signed-in account viewing the post list
- **When** they long-press a post and choose "Cross-post" from the context menu
- **Then** the new-post composer opens with the post's title and link pre-filled and no
  community chosen
- **And** the body is left empty (the feed doesn't carry the post's full body)

### Cross-post from post detail

- **Given** a signed-in account viewing an open post
- **When** they open the "•••" overflow menu and choose "Cross-post"
- **Then** the new-post composer opens with the post's title and link pre-filled
- **And**, if the post has a body, the composer's body is seeded with
  `cross-posted from: <the post's link>` followed by the body quoted line-by-line

### Picking the target community

- **Given** the cross-post composer is open
- **When** the user taps the community picker and selects a community
- **Then** Post becomes available, and submitting creates the new post in the chosen
  community via the same durable, optimistic post-creation flow as an ordinary new post
  (pending post-detail screen, background send, retry on failure)

### A stale draft doesn't clobber the cross-post

- **Given** a previously abandoned, unsent draft exists for a brand-new post with no
  community chosen
- **When** the user opens a cross-post
- **Then** the composer shows the cross-post's seeded title/link/body, not the stale draft

### Signed-out cross-post is blocked

- **Given** a signed-out account
- **When** they choose "Cross-post" from either surface
- **Then** a "Sign in to post" alert is shown and the composer is not presented

### Opening a post with cross-posts shows the section

- **Given** a post whose server detail response reports two other posts sharing its link
- **When** the post is opened
- **Then** the header shows a "Cross-posted to 2 communities" section listing both, in the
  server's order, each showing its `c/name@instance` handle and a score/comment-count line

### Tapping a cross-post opens it

- **Given** the "Cross-posted to N communities" section is showing
- **When** the user taps one of the listed cross-posts
- **Then** that post opens in-app (pushed on iPhone, opened in the detail column on iPad),
  even when it lives on a different instance than the currently-open post

### A post with none shows no section

- **Given** a post whose server detail response reports no other posts sharing its link
  (or a post opened from a feed row that hasn't had its full detail fetched yet)
- **When** the post is opened
- **Then** no cross-posts section is shown

### Two communities share a link, and the feed collapses them

- **Given** the loaded feed contains a post in c/technology and a post in c/news that
  both link to the same article, with "Group Cross-posts" on (the default)
- **When** the feed renders
- **Then** only the first of the two (in feed order) is shown, with an "Also in c/news"
  (or "Also in c/technology", depending on which came first) line under it
- **And** the second post's row does not appear

### Turning the preference off shows both rows

- **Given** the two-community grouping from the scenario above
- **When** the user turns "Group Cross-posts" off in Settings → Display
- **Then** the feed immediately shows both posts as separate rows again, with no
  affordance line, live and without a reload

### Jumping to a collapsed sibling from the context menu

- **Given** a primary post's cell shows an "Also in ..." affordance
- **When** the user long-presses it and chooses a community from the "Also posted in"
  submenu
- **Then** that community's post opens in-app, the same as tapping any other post in the
  feed

### Cross-posts that never load together stay ungrouped

- **Given** the same link posted to two communities, but only one of those posts is in
  any page the feed has loaded this session
- **When** the feed renders
- **Then** the loaded post shows with no "Also in ..." affordance — grouping only sees
  posts the feed has actually fetched, not the link's full set of cross-posts server-side

## Not supported / out of scope

- The feed's cross-post action seeds title + link only; only the post-detail overflow's
  cross-post (where the full post is already loaded) includes the quoted-body
  attribution.
- No duplicate warning or suggested target community *when creating* a cross-post — the
  user picks the community manually via the ordinary community picker. (This is
  different from feed grouping, above, which collapses duplicates that are already
  posted and already loaded into the feed; it has no bearing on composing.)
- Feed grouping has no cross-instance awareness beyond what's already loaded — it doesn't
  query other instances or the server for a link's full cross-post set the way the
  post-detail "Cross-posted to N communities" section does.
- The cross-posts section is a one-shot read taken when the post loads and on
  pull-to-refresh; it does not live-update if a cross-post is created elsewhere while the
  post is on screen.
- Editing the pre-filled title, link, body, or NSFW flag before posting works exactly
  like an ordinary new post; see [New post](new-post.md) for that behavior.
