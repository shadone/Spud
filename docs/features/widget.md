# Home Screen widget (top posts)

- **Surfaces:** `widget`
- **Status:** shipped
- **Related:** [Feeds and sorting](feeds-and-sorting.md), [Feed loading and pagination](feed-loading.md), [Post detail and comments](post-detail-and-comments.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Spud ships a Home Screen widget that shows the top posts of a feed at a glance. You pick a feed category and a sort when you add or edit the widget; it then lists the top posts with their title, community, score, and comment count, refreshing about once an hour. Tapping a post opens that post's detail directly in the app.

## Behavior and rules

- **Top posts of a chosen feed.** The widget shows the top posts from a feed — the same standard feeds as the app: All, Local, Subscribed, or Moderator view. The number of posts depends on the widget size.
- **Configurable category and sort.** When adding or editing the widget you choose a Category (the feed) and a Sort. The sort options match the app's, including Hot, New, Active, Most Comments, New Comments, and the Top time ranges (6 hours through All time). The default configuration is the Subscribed feed sorted by Hot. There is no account or instance picker — the widget uses your default account, falling back to a signed-out view that maps Subscribed and Moderator view to All.
- **Sizes.** The widget supports the small, medium, and large Home Screen sizes plus the inline and rectangular lock-screen accessory sizes. Medium and small show three posts, large shows six under a "Top posts" header, and the accessory sizes show a single post. The extra-large and circular families are not supported.
- **What each post shows.** A post row shows its title, community name and instance host, upvote score, and comment count, with a small thumbnail for image posts (or a placeholder glyph for text posts). The smaller sizes drop the instance host line.
- **Reads the shared database, refreshes hourly.** The widget reads through the app's data layer against the shared App Group database — the same store the app writes — so it reflects your account and subscriptions. To keep its data current it fetches the chosen feed from the server and caches thumbnails when its timeline rebuilds, roughly once an hour.
- **Tap opens the post in the app.** Each post links to its detail via a deep link into the app (`info.ddenis.spud://internal/post?...`); on the accessory sizes the whole widget links to its single post. The app handles that link by opening the post's detail.

## Scenarios

### The widget shows top posts of the chosen feed

- **Given** the widget added to the Home Screen, configured for a feed and sort
- **When** I look at the widget
- **Then** it lists the top posts of that feed
- **And** each row shows the title, community, score, and comment count

### Choosing the category and sort

- **Given** I am adding or editing the widget
- **When** I open its configuration
- **Then** I can pick a Category (All, Local, Subscribed, or Moderator view) and a Sort (Hot, New, Top time ranges, and so on)
- **And** the widget reloads to show that feed

### Post count follows the widget size

- **Given** the widget on the Home Screen
- **When** I use the medium or small size
- **Then** three posts are shown
- **And** the large size shows six under a "Top posts" header, while the accessory sizes show one

### Tapping a post opens it in the app

- **Surfaces:** `widget`
- **Given** the widget showing posts
- **When** I tap a post
- **Then** the app opens that post's detail directly

### The widget refreshes its data periodically

- **Given** the widget on the Home Screen
- **When** about an hour passes
- **Then** the widget rebuilds its timeline, refetching the feed and updating the posts shown

## Not supported / out of scope

- **No account or instance selection.** The widget uses your default account; it does not offer a per-widget account or instance picker.
- **No interaction beyond tapping a post.** You cannot vote, save, or scroll within the widget — it is a read-only glance that deep-links into the app.
- **No extra-large or circular sizes.** Only small, medium, large, and the inline and rectangular accessory families are supported.
- **No saved or single-community feed.** The category options are the standard frontpage feeds (All, Local, Subscribed, Moderator view); the widget does not target a specific community or your saved posts.
