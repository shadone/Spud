# Post peek (context-menu preview)

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [post-thumbnails.md](post-thumbnails.md), [swipe-actions.md](swipe-actions.md), [mark-read-and-hiding.md](mark-read-and-hiding.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Long-pressing a post in the feed raises a floating preview (a "peek") above its context menu — an Apollo-style touch. The peek is a compact card showing the post's image (for image and video posts), its full title, and its full body text. Because the feed cell truncates the body, the peek is where you read a post's text without opening it. Tapping the peek commits to opening the post and its comments.

## Behavior and rules

- **Triggered by long-press.** A long-press on a post cell presents the system context menu with the post peek floating above it.
- **Peek contents.** The peek shows, top to bottom: an optional image, the post title (untruncated, up to four lines), and the full post body rendered from Markdown (up to twelve lines). A post with no body omits the body area.
- **Image in the peek.** For an image post the peek shows the post image; for a video post it shows the poster frame. External-link and text posts show no image — title and body only. The image area is a fixed-height letterbox so the card stays a sensible size regardless of the source aspect ratio.
- **Self-sizing card.** The peek sizes itself to its content width and fitted height.
- **Tapping commits to the post.** Tapping the peek dismisses the menu and opens the post detail (the post and its comments).
- **The peek accompanies a context menu.** Alongside the peek the menu offers post actions (upvote, downvote, save/unsave, share, and moderation actions where applicable); those actions are a separate concern from the preview described here.

## Scenarios

### Long-press raises a peek

- **Given** a post in any feed
- **When** I long-press the cell
- **Then** a floating preview appears above the context menu
- **And** it shows the post title and full body text

### The peek shows an image post's image

- **Given** an image post
- **When** I long-press it
- **Then** the peek shows the post image above the title and body

### The peek shows a video post's poster

- **Given** a video post with a poster frame
- **When** I long-press it
- **Then** the peek shows the poster frame above the title and body

### A text post peeks without an image

- **Given** a text-only or external-link post
- **When** I long-press it
- **Then** the peek shows the title and body with no image

### Reading the full body in the peek

- **Given** a post whose body is truncated in the feed cell
- **When** I long-press it
- **Then** the peek renders the full body so I can read it without opening the post

### Tapping the peek opens the post

- **Given** the peek is showing
- **When** I tap it
- **Then** the menu dismisses and the post detail opens

## Not supported / out of scope

- This documents only the preview/peek. The post actions in the same context menu (upvote, downvote, save, share, and the moderation submenu) are their own features.
- The peek is read-only: it has no buttons, no inline image viewer, and no scrolling — long bodies are clamped (twelve lines) rather than scrollable.
- The peek renders a static poster frame for video posts and a still image for image posts; it never plays media. Animated GIFs are not animated in the peek.
- Per-comment preview/peek in a post's comment thread is a separate feature and is not covered here.
