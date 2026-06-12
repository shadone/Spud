# Sharing

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Post detail and comments](post-detail-and-comments.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Share a post's or comment's link through the system share sheet, and open a post in an
in-app Safari view. The shared URL prefers the content's federation permalink so it
resolves on any instance, falling back to a URL built from your home instance.

## Behavior and rules

- **Share a post.** The post toolbar's share button, the post's context-menu Share, and (where configured) a post share swipe present the system share sheet with the post's URL.
- **Share a comment.** A comment's context-menu Share (and a share swipe slot, where configured) presents the share sheet with the comment's URL.
- **Canonical URL preferred.** The shared URL uses the content's federation permalink (its `ap_id`) when available; otherwise it is built from your account's home instance as `<instance>/post/<id>` or `<instance>/comment/<id>`. If no URL can be formed, a warning haptic fires and nothing is shared.
- **System share sheet.** Sharing presents a `UIActivityViewController` carrying the URL; on iPad it anchors its popover to the originating button or cell. A light haptic fires on present.
- **Open in Safari.** The post toolbar's Safari button opens the post in an in-app `SFSafariViewController` built from `<instance>/post/<id>`. This always opens in-app — it does not honor the external-link preference (that preference governs links tapped inside content, not this button).
- **Links inside content** (markdown links in the post body or a comment) route through the app's link handler: person and community links navigate in-app, image and video links open the media viewer / player, and other external links open per the external-link preference (in-app Safari view or system Safari).

## Scenarios

### Share a post

- **Given** an open post
- **When** I tap the share button or choose Share from the post's context menu
- **Then** the system share sheet appears with the post's URL

### Share a comment

- **Given** a comment
- **When** I long-press it and choose Share
- **Then** the system share sheet appears with the comment's URL

### Shared URL prefers the permalink

- **Given** a post that carries a federation permalink
- **When** I share it
- **Then** the permalink URL is shared
- **And** when there is no permalink, a URL built from my home instance is shared instead

### Open a post in Safari

- **Given** an open post
- **When** I tap the Safari button
- **Then** the post opens in an in-app Safari view

## Not supported / out of scope

- **No share-as-image.** Sharing carries the URL only; there is no render-the-post-as-an-image option.
- **No community-URL share action** from the post-detail surface (only post and comment URLs are shared here).
- The Safari button always opens in-app and does not follow the external-link preference; only links tapped inside content follow that preference.
- Configuring a share swipe slot is part of [swipe-actions.md](swipe-actions.md), not this feature.
