# Open in Spud (Safari extension)

- **Surfaces:** `share-extension`, `iphone`, `ipad`
- **Status:** partial — ships as a Safari web extension scoped to a single instance's post pages, not a system share/action sheet item, and only post URLs are routed
- **Related:** [Sharing](sharing.md), [Post detail and comments](post-detail-and-comments.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Spud ships an "Open in Spud" extension that sends a Lemmy post you are viewing in Safari into the app, opening it on the post's detail screen. It is the reverse of [Sharing](sharing.md): sharing sends a Spud post out to the system share sheet, while this opens a web post in. The extension is a Safari web extension — it runs on a Lemmy post page in Safari and redirects to the app via a deep link — rather than an item in the system share or action sheet.

## Behavior and rules

- **Safari web extension.** "Open in Spud" is a Safari web extension, not a system share or action extension. It does not appear in the share sheet; it activates by running a content script on matching pages in Safari.
- **Scoped to post pages on one instance.** The content script runs only on post pages of `discuss.tchncs.de` — URLs of the form `https://<host>/post/<id>`. On a matching page it reads the page URL, extracts the instance host and the numeric post id, and redirects to the app.
- **Routes via a custom-scheme deep link.** The extension redirects the page to `info.ddenis.spud://internal/post?postId=<id>&instance=<host>`. The app registers that custom URL scheme; there is no universal (https) link path.
- **The app opens the post's detail.** When the app receives the deep link it parses the post id and instance, resolves the matching account, and opens that post's detail screen. This is the same internal post link the [widget](widget.md) emits, so the in-app landing is identical.
- **Post links only.** Although the app's internal link vocabulary also defines person and community links, the Safari extension only ever emits a post link, and the app's handlers for person and community deep links are not yet implemented. End to end, only a post URL opens a screen.

## Scenarios

### Opening a Lemmy post from Safari into the app

- **Surfaces:** `share-extension`, `iphone`, `ipad`
- **Given** I am viewing a post page on `discuss.tchncs.de` in Safari with the extension enabled
- **When** the extension runs on the page
- **Then** Safari redirects to the Spud deep link for that post
- **And** the app opens on that post's detail screen

### Non-post pages are ignored

- **Surfaces:** `share-extension`
- **Given** a page in Safari that is not a `discuss.tchncs.de` post page
- **When** I am browsing it
- **Then** the extension does not redirect, and nothing opens in the app

## Not supported / out of scope

- **Not a share/action sheet item.** "Open in Spud" does not appear in the system share sheet or action menu; it is a Safari web extension only, so it has no entry point from non-Safari apps.
- **One instance only.** The content script is scoped to `discuss.tchncs.de` post pages; posts on other Lemmy instances in Safari are not handled.
- **Post URLs only.** Comment, community (`/c/...`), user (`/u/...`), and instance-home URLs are not handled. Person and community deep links are defined in the app but their handlers are unimplemented, so only post links open a screen.
- **No universal-link path.** Routing is the custom `info.ddenis.spud://` scheme; the app declares no associated domains, so a Lemmy https link is not deep-linked by the system.
