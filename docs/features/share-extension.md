# Open in Spud (Safari banner + Share extension)

- **Surfaces:** `share-extension`, `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Sharing](sharing.md), [External link handling](external-link-handling.md), [Post detail and comments](post-detail-and-comments.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Spud opens a Lemmy link you find anywhere in iOS — a post, comment, community, or
user — directly on the matching screen in the app. There are two entry points,
both instance-agnostic: a **Safari banner** that appears on recognized Lemmy
pages, and an **"Open in Spud" share-sheet action** available from any app. It is
the reverse of [Sharing](sharing.md): sharing sends a Spud link out to the system
share sheet; this brings a Lemmy link in.

Both entry points are thin — they hand the page URL to the app as a `resolve` deep
link and the app does all the work: it resolves the URL via Lemmy `resolve_object`
under your default account and routes to the post, community, or user (a comment
opens its parent post). Because resolution runs against your own instance, links
on any federated instance work, including ones the app has never seen.

## Behavior and rules

- **Safari banner, no hijack.** On a recognized Lemmy content page in Safari a
  small dismissible "Open this in Spud?" banner appears with an Open button.
  Tapping Open switches to the app; dismissing hides it for that page. Reading in
  Safari is never silently redirected.
- **Banner runs on known instances.** The content script is scoped to a bundled
  allowlist of Lemmy instance hosts (generated from the Explorer instance
  directory, ~500 instances), and only shows the banner on
  `/post/`, `/comment/`, `/c/`, and `/u/` pages. Instances added after the app was
  built are not in the allowlist — use the share sheet for those.
- **Share-sheet action, any instance.** "Open in Spud" appears in the system share
  sheet for web URLs. It takes the shared URL, wraps it in the app's deep link, and
  opens the app. It is instance-agnostic — it does not depend on the allowlist — so
  it covers the long tail the Safari banner misses.
- **One deep link, one resolver.** Both paths emit
  `info.ddenis.spud://internal/resolve?url=<page URL>`. The app resolves it and
  routes by type: a post opens post detail, a community opens the community screen,
  a user opens their profile, and a comment opens its parent post.
- **Graceful failure.** If the URL is not a resolvable Lemmy object (a non-Lemmy
  page shared into the action, or an unfederated link), the app logs it and plays a
  warning haptic rather than opening a blank screen.

## Scenarios

### Open a Lemmy post from Safari

- **Surfaces:** `share-extension`, `iphone`, `ipad`
- **Given** I am viewing a post page on an allowlisted Lemmy instance in Safari
- **When** I tap Open on the "Open this in Spud?" banner
- **Then** the app opens on that post's detail screen

### Open any Lemmy link from another app

- **Surfaces:** `share-extension`
- **Given** a Lemmy URL (post, comment, community, or user) in another app
- **When** I share it and choose "Open in Spud"
- **Then** the app resolves it and opens the matching screen
- **And** this works even for an instance not in the Safari allowlist

### A community or user link opens its screen

- **Given** a `/c/<name>` or `/u/<name>` Lemmy URL
- **When** I open it via the banner or the share sheet
- **Then** the app opens that community or person screen

### A comment link opens its post

- **Given** a `/comment/<id>` Lemmy URL
- **When** I open it
- **Then** the app opens the comment's parent post

### Dismissing the banner

- **Given** the banner shown on a Lemmy page
- **When** I tap the dismiss control
- **Then** the banner is removed and does not reappear for that page

## Not supported / out of scope

- **No scroll-to-comment yet.** A comment link opens its parent post but does not
  yet scroll to or highlight the specific comment. Resolving a comment to its
  on-screen row needs the comment's context loaded into the tree; this is a planned
  follow-up.
- **No instance-home open.** A bare instance URL (e.g. `lemmy.world`) is not routed
  to an in-app screen.
- **No Universal Links.** Spud declares no associated domains — it cannot, since it
  does not control the federated instances' `/.well-known/`. Routing is the custom
  `info.ddenis.spud://` scheme via the banner and share action.
- **Allowlist staleness.** The Safari banner's instance list is fixed at build time
  and regenerated per release (`make safari-matches`); brand-new instances rely on
  the share-sheet action until the next release.
