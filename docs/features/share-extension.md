# Open in Spud (Safari banner + Share extension)

- **Surfaces:** `share-extension`, `iphone`, `ipad`
- **Status:** shipped — the Safari banner, the toolbar popup, and the "Open in Spud" share/action all work
- **Related:** [Sharing](sharing.md), [External link handling](external-link-handling.md), [Post detail and comments](post-detail-and-comments.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Spud opens a Lemmy link you find anywhere in iOS — a post, comment, community, or
user — directly on the matching screen in the app. There are three entry points: a
**Safari banner** and a **toolbar popup**, both on recognized (allowlisted) Lemmy
pages, and an **"Open in Spud" share-sheet action** available from any app and
instance-agnostic. It is
the reverse of [Sharing](sharing.md): sharing sends a Spud link out to the system
share sheet; this brings a Lemmy link in.

All three entry points are thin — they hand the page URL to the app as a deep link
and the app does all the work: it resolves the URL via Lemmy `resolve_object` under
your default account and routes to the post, community, or user (a comment opens its
parent post). They emit two deep-link forms (see below) — the banner and popup share
one — but both resolve the same way in-app. Because resolution runs against your own instance,
links on any federated instance work, including ones the app has never seen.

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
- **Toolbar popup, known instances.** The Safari toolbar button opens a popup
  that offers a single "Open in Spud" on any page of a known instance (the same
  bundled allowlist the banner uses — the popup detects it via the content
  script's presence, not a duplicated host list). Unlike the banner it is
  available on non-content pages (instance home, search) and after the banner is
  dismissed. On a non-allowlisted host or a non-Lemmy page it shows an inactive
  "Not a Lemmy instance" message instead of an action.
- **Share-sheet action, any instance.** "Open in Spud" appears in the system share
  sheet for web URLs. It takes the shared URL, wraps it in the app's deep link, and
  opens the app. It is instance-agnostic — it does not depend on the allowlist — so
  it covers the long tail the Safari banner misses.
- **Two deep-link forms, one resolver.** The Safari banner and toolbar popup emit
  `info.ddenis.spud://internal/resolve?url=<page URL>`; the share/action extension
  emits the `objectAtURL` internal link (`URL.SpudInternalLink.objectAtURL`). Both
  are decoded by the app's URL router and resolved via `resolve_object`, then routed
  by type: a post opens post detail, a community opens the community screen, a user
  opens their profile, and a comment opens its parent post.
- **Graceful failure.** If the URL is not a resolvable Lemmy object (a non-Lemmy
  page shared into the action, or an unfederated link), the app logs it and plays a
  warning haptic rather than opening a blank screen.

## Scenarios

### Open a Lemmy post from Safari

- **Surfaces:** `share-extension`, `iphone`, `ipad`
- **Given** I am viewing a post page on an allowlisted Lemmy instance in Safari
- **When** I tap Open on the "Open this in Spud?" banner
- **Then** the app opens on that post's detail screen

### Open the current instance page from the toolbar popup

- **Surfaces:** `share-extension`, `iphone`, `ipad`
- **Given** I am on any page of a known Lemmy instance in Safari
- **When** I tap the Spud toolbar button and choose "Open in Spud"
- **Then** the app opens and resolves that page (a post/community/user opens its screen)

### The popup is inactive off a known instance

- **Surfaces:** `share-extension`, `iphone`, `ipad`
- **Given** I am on a non-Lemmy page (or a Lemmy instance not in the allowlist)
- **When** I open the Spud toolbar popup
- **Then** it shows "Not a Lemmy instance" and offers no action

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

- **Comment scroll covers the loaded tree.** A comment link opens its parent post,
  scrolls to the resolved comment (expanding collapsed ancestors), and flashes it.
  If the target isn't in the post's loaded comment tree (a very deep or paginated
  comment beyond the fetched set), it lands on the post without scrolling rather
  than fetching that single comment's context — a follow-up.
- **No instance-home open.** A bare instance URL (e.g. `lemmy.world`) is not routed
  to an in-app screen. The toolbar popup still offers "Open in Spud" on such a
  page (it acts on any known-instance page), but the app cannot resolve it and
  plays a warning haptic — improving that feedback is a follow-up that also
  affects the banner.
- **No Universal Links.** Spud declares no associated domains — it cannot, since it
  does not control the federated instances' `/.well-known/`. Routing is the custom
  `info.ddenis.spud://` scheme via the banner and share action.
- **Allowlist staleness.** The Safari banner's instance list is fixed at build time
  and regenerated per release (`make safari-matches`); brand-new instances rely on
  the share-sheet action until the next release.
