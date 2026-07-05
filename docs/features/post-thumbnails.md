# Post thumbnails and media badges

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [feeds-and-sorting.md](feeds-and-sorting.md), [post-peek.md](post-peek.md), [swipe-actions.md](swipe-actions.md), [nsfw-content.md](nsfw-content.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Each post in the feed shows a small square thumbnail next to its title and subtitle. What the thumbnail shows depends on the post's content: an image post shows the image, a video post shows its poster frame with a play indicator, an external link with an embedded preview image shows that image, and a text-only post shows a placeholder icon. Animated (GIF) image posts carry a small "GIF" badge so they read as playable at a glance.

## Behavior and rules

- **Content type drives the thumbnail.** Spud classifies a post's URL into image, video, external link, or text/empty, and picks the thumbnail accordingly. Image detection is by file extension (`.jpg`, `.jpeg`, `.png`, `.webp`, `.gif`); a post is video either by a playable file extension (`.mp4`, `.mov`, `.m4v`) or by being a recognized video host (currently streamable.com). A recognized-host video shows the server thumbnail as its poster with the play indicator, just like a direct video post.
- **Image post.** Shows the post's thumbnail image (or the full image if no thumbnail). Tapping it opens the full-screen image viewer; the already-loaded thumbnail is handed to the viewer for an instant first frame.
- **GIF badge.** When an image post's full image is an animated GIF, the inline thumbnail shows a static frame with a small dark rounded "GIF" badge in its lower-left corner. The badge signals the post plays; the animation itself plays in the full-screen viewer, not inline.
- **Video post.** Shows the poster frame (when the post carries one) with a centered play indicator overlaid; tapping plays the video. A video post with no poster shows the text placeholder behind the play indicator.
- **External-link post.** When the link carries an embed/preview image, the thumbnail shows that image inline. It is not tappable as an image — tapping it falls through to opening the post (mirroring the detail view's link preview). A link with no preview image shows the text placeholder.
- **Text post.** Shows a placeholder icon on a tinted background. The placeholder is decorative; tapping it falls through to opening the post.
- **Broken image.** If a thumbnail image fails to load, the cell shows a broken-image marker in place of the thumbnail.
- **Thumbnail position is configurable.** A Settings option places the thumbnail on the leading (left) edge, the trailing (right) edge, or hides it entirely; when hidden the title and subtitle take the full width and no thumbnail image is loaded.
- **Thumbnails are square and downsampled.** The thumbnail is a fixed 64-point square with rounded corners; images are downsampled to that size so the cache holds cell-sized images.
- **Pre-warming.** As you scroll, Spud warms the image cache a few rows ahead using the same thumbnail URL the cell would load, so thumbnails are ready by the time the row appears.

## Scenarios

### An image post shows a tappable thumbnail

- **Given** an image post in a feed
- **When** the cell appears
- **Then** its thumbnail shows the post image
- **And** tapping the thumbnail opens the full-screen image viewer

### A GIF post is badged

- **Given** an image post whose image is an animated GIF
- **When** the cell appears
- **Then** the thumbnail shows a static frame with a "GIF" badge
- **And** tapping it opens the viewer, where the GIF plays

### A video post shows a play indicator

- **Given** a post linking to a playable video (mp4 / mov / m4v)
- **When** the cell appears
- **Then** the thumbnail shows the poster frame with a centered play icon
- **And** tapping it plays the video

### An external link shows its embed image

- **Given** a link post that carries an embed preview image
- **When** the cell appears
- **Then** the thumbnail shows that preview image inline
- **And** tapping the thumbnail opens the post rather than an image viewer

### A text post shows the placeholder

- **Given** a text-only post (no link, no image)
- **When** the cell appears
- **Then** the thumbnail shows the text-post placeholder icon

### Hiding the thumbnail widens the text

- **Surfaces:** `iphone`, `ipad`
- **Given** the thumbnail position is set to Hidden in Settings
- **When** I view the feed
- **Then** posts show title and subtitle across the full width with no thumbnail

### A failed thumbnail shows the broken state

- **Given** an image post whose thumbnail fails to load
- **When** the cell finishes loading
- **Then** it shows a broken-image marker

## Not supported / out of scope

- **NSFW thumbnails.** When "Blur NSFW" is on and "Show NSFW" is on, thumbnails for NSFW posts are covered by a frosted-glass overlay until tapped. This is governed by the NSFW preference, not by thumbnail-display settings; see [NSFW content visibility and blur](nsfw-content.md).
- The inline thumbnail never animates — a GIF shows a static frame plus the badge; animation happens only in the full-screen viewer.
- Non-AVFoundation video containers (e.g. webm, mkv) that are not a recognized video host are treated as external links, not video posts, and get no play indicator.
- No badge other than "GIF" is shown on feed thumbnails; the badge component is generic but only the GIF case is wired up here.
- Thumbnail size is fixed (64-point square) and is not user-configurable; only its position (left / right / hidden) is.
- The full-screen image viewer, GIF playback, and inline/full-screen video player are separate Media capabilities and are not described here.
