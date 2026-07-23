# Media viewer zoom transition (v2) — design

Date: 2026-07-23
Branch: `feat/media-zoom-v2`
Supersedes: `docs/superpowers/specs/2026-06-21-media-viewer-zoom-transition-design.md`
Status: approved, implementing

## Why a v2

The June 2026 design (`feat/media-viewer-zoom-transition`, five commits, never
merged) is sound in mechanism but was written against a codebase that has since
moved a great deal — `PostDetailViewController` and `PostListViewController` were
largely rewritten, and a new media-viewer entry point (**Activity**) landed. A
trial merge produces five content conflicts in exactly the files that changed
most. Rather than resolve June's diff against July's architecture, this v2
re-applies the *design* on current `main`, keeps the parts that port verbatim,
rewrites the per-call-site resolvers against today's structure, and adds two
things the old spec never had: the Activity/Person-Posts entry points and
**scroll-to-reveal on dismiss**.

The original branch and its spec are retained as provenance until this lands.

## Goal

When the user taps an image that opens the full-screen media viewer, the viewer
should *expand from the tapped view* into full screen and, on dismiss, *shrink
back into it* — the standard hero interaction (Photos, Apollo, Ivory). Today the
viewer presents with a flat cross-dissolve. When the source view is no longer on
screen, the transition degrades gracefully rather than animating from a stale
frame.

## Decision

Adopt the **native iOS 18 zoom transition**
(`UIViewController.preferredTransition = .zoom(options:sourceViewProvider:)`),
not a hand-rolled `UIViewControllerAnimatedTransitioning`.

Rationale (unchanged from v1):

- Minimum deployment target is iOS 18.0, so the API is always available.
- It provides present-expand *and* an interactive, continuously
  grab/drag/reverse dismiss that shrinks back into the source, with no custom
  frame-interpolation code.
- Apple's contract solves the hardest correctness problem: the source provider
  closure is re-invoked on **both present and dismiss**, and Apple instructs
  callers to re-resolve the source view by a stable identifier at call time
  rather than capture a `UIView`/`IndexPath`. That is exactly what makes reused
  feed/comment cells safe.

Reference: Apple "Enhancing your app with fluid transitions" and
`UIViewController.Transition.zoom(options:sourceViewProvider:)` (iOS 18.0+).

## Core seam

One shared mechanism; everything else is per-call-site resolvers.

### 1. `zoomSource` parameter

`UIViewController.presentMediaViewer(...)` and
`MediaViewerViewController.make(...)` / `init(...)` gain:

```swift
zoomSource: ((MediaItem) -> UIView?)? = nil
```

A **re-resolving** closure: given the item currently shown, return its live
on-screen source view, or `nil`. Stored on the viewer; called by the system on
present and dismiss. Call sites capture their host weakly and look the view up
by a stable id each time — never capture the view itself.

### 2. Viewer adoption

`MediaViewerViewController` decides its transition mode once, at init:

```swift
// Reduce Motion → skip zoom, use the cross-dissolve fallback (which already
// collapses to an instant cut under Reduce Motion).
let zoomSource = UIAccessibility.isReduceMotionEnabled ? nil : zoomSource
usesZoomTransition = zoomSource != nil

if let zoomSource {
    preferredTransition = .zoom { [weak self] _ in
        guard let self else { return nil }
        return zoomSource(items[currentIndex])   // current page → its source
    }
    // do NOT set modalPresentationStyle = .custom / transitioningDelegate
} else {
    modalPresentationStyle = .custom
    transitioningDelegate = self                  // existing cross-dissolve
}
```

Reading `items[currentIndex]` inside the closure makes multi-image dismiss
correct: if the user paged away, the provider matches the *current* item (and
returns `nil` when that page has no on-screen source).

### 3. Dismiss & gesture reconciliation

- **Zoom mode:** do not install the viewer's custom swipe-down pan; the system
  provides the interactive drag-to-shrink dismiss. The explicit close button
  still calls `dismiss(animated: true)`, which plays the zoom-out. The per-page
  `ZoomableImageView` keeps its own pinch / pan / double-tap zoom. When an image
  is zoomed in, the system dismiss gesture must defer to the inner scroll-view
  pan — the same min-zoom gating the current custom pan already encodes via
  `ZoomableImageView.isZoomed` (device-verify, risk S2 below).
- **Fallback mode:** unchanged — custom swipe-down pan + `MediaViewerTransition`
  cross-dissolve. `MediaViewerTransition` is **kept**, not deleted.

### 4. Markdown body-image lookup

`SpudMarkdownKit` gains `MarkdownBodyView.zoomSourceView(forImageURL:)` — walks
the rendered block tree to the loaded `ImageBlockView`'s rounded box for that
URL, or `nil` when no such image is currently rendered. Ports verbatim from the
v1 branch (`ImageBlockView.zoomSourceView(forImageURL:)` guards on
`isLoaded && url == imageURL`; only the loaded state is tappable). This is the
one piece lifted directly.

## Entry points (current `main`)

Every call site that opens the viewer gets a resolver keyed by a stable id and
re-resolved live. Only the web-link case, which has no on-screen view, keeps the
plain cross-dissolve.

| # | Entry point | Source view | Key | Scroll-to-reveal? |
|---|---|---|---|---|
| 1 | Feed thumbnail | `PostListPostContentView.thumbnailView` | `serverPostId` → visible cell | Yes |
| 2 | Post-detail header image | `PostDetailHeaderCell.postImageView` | visible header cell | No (single cell) |
| 3 | Post-detail body image | `MarkdownBodyView.zoomSourceView(forImageURL:)` | header cell + URL | No |
| 4 | Comment body image | same, in `PostDetailCommentCell` | comment id + URL | No |
| 5 | Person profile body image | same, in persistent header | URL | No |
| 6 | Person "Posts" tab cell | `PostListPostContentView.thumbnailView` | `serverPostId` (reuses #1 resolver) | Yes |
| 7 | Community profile body image | same, in persistent header | URL | No |
| 8 | Activity post image | post-content view's thumbnail | `serverPostId` / URL | Yes |
| 9 | Web-link-classified image | none (URL only) | n/a — keeps cross-dissolve | n/a |

Changes from the v1 table: #8 (Activity) is new — it did not exist in June; #6
(Person Posts) is called out because it shares the feed's cell type and so
reuses the #1 resolver (DRY — one resolver, two hosts).

## Scroll-to-reveal on dismiss

The step past v1. When the source cell is off screen at dismiss time, instead of
degrading to a fade the closure scrolls the underlying list to bring the cell on
screen, then resolves to it — Photos behavior.

Mechanism: the `zoomSource` closure, when it finds no visible cell for the id,
asks its host to scroll that id into view **synchronously and non-animated**
(`scrollToRow(at:at:.none, animated: false)` + `layoutIfNeeded()`), then
re-resolves the now-visible cell's view. iOS 18's `.zoom` invokes the provider
during the dismiss animation setup, so a synchronous scroll-then-resolve inside
the closure lands the cell before the morph is committed. Non-animated so the
reveal does not compound with the zoom.

Applied to **list-backed surfaces only**, where a stable `serverPostId →
indexPath` mapping exists:

- **Yes:** feed (#1), Person "Posts" tab (#6), Activity (#8).
- **No (keep fade):** body images inside post-detail and comment threads
  (#2–#5, #7). Scrolling a deep thread to an arbitrary inline image on dismiss
  is disorienting and the tree may have re-laid-out; a fade is the honest
  degradation there.

If a post genuinely left the data set (feed refreshed, post filtered out), the
id maps to no indexPath → the resolver returns `nil` → fade. Scroll-to-reveal
only helps the common case where the cell exists but is scrolled off.

## Accessibility

- **Reduce Motion:** zoom path skipped entirely (gated at init, above); the
  cross-dissolve fallback is used.
- **VoiceOver:** the viewer's existing labels, alt-text pill, and the
  `mediaViewerImage` accessibility identifier are untouched. Verify focus lands
  on the image after the zoom present and returns to the source element on
  dismiss — the one a11y behavior the zoom changes.

## iPad / split view

The viewer presents modally over the full screen from either split column. The
source resolves within whichever column's list is on screen; a source in a
collapsed/hidden column resolves `nil` → fade. Verify in the regular size class /
split view, not just compact.

## Error handling / graceful degradation

A single safety net at every entry point: any resolver returns `nil` when it
cannot find a live, loaded source view (scrolled off and not reveal-able,
recycled, wrong URL). A `nil` source makes the system fall back to a non-source
transition. Worst case anywhere is "behaves like today (fade)", never broken or
animating from a stale frame.

## Components changed

- `Spud/Utils/UIViewController+MediaViewer.swift` — add `zoomSource` param.
- `Spud/Scenes/MediaViewer/MediaViewerViewController.swift` — store provider,
  branch transition mode at init, gate custom pan install on
  `usesZoomTransition`.
- `SpudMarkdownKit/Rendering/MarkdownBodyView.swift`,
  `SpudMarkdownKit/Rendering/ImageBlockView.swift` — `zoomSourceView(forImageURL:)`
  lookup (ported from v1).
- `Spud/Scenes/PostList/PostListViewController.swift` (+ `PostListPostContentView`)
  — `serverPostId → thumbnailView` resolver + scroll-to-reveal; pass `zoomSource`
  at the call site. Shared by the feed and the Person Posts tab.
- `Spud/Scenes/PostDetail/Content/PostDetailViewController.swift` — header-image
  resolver + body-image resolvers (post + comment); pass `zoomSource` at each
  call site except the web-link case.
- `Spud/Scenes/Person/Content/PersonViewController.swift` (+ `PersonHeaderView`),
  `Spud/Scenes/Community/Content/CommunityViewController.swift`
  (+ `CommunityHeaderView`) — body-image resolvers.
- `Spud/Scenes/Activity/ActivityViewController.swift` — post-image resolver +
  scroll-to-reveal.
- `MediaViewerTransition` is kept (fallback path).

## Testing

**Unit (simulator, autonomous gate):**

- `MarkdownBodyView.zoomSourceView(forImageURL:)` returns the right box / `nil`
  (ports the v1 branch's 80-line test).
- The feed/Activity `serverPostId → thumbnailView` resolver returns the visible
  cell's view / `nil` for an off-screen id.
- Scroll-to-reveal maps `serverPostId → indexPath` correctly and returns `nil`
  for an id absent from the data set.

**Mechanics (simulator, agent):** present/dismiss zoom, source re-resolution
after scrolling, scroll-to-reveal landing the cell, Reduce Motion fallback,
`nil`-source degradation — captured with screen recordings.

**Feel (device, human):** frame rate and the interactive drag-to-shrink dismiss,
against the checklist below. The simulator cannot meaningfully confirm an
interactive transition.

## Risks — device (TestFlight/local) only

- **S1 — modal present + `.zoom`.** Apple documents `.zoom` mainly with
  navigation push; the viewer presents modally. `preferredTransition` is a
  general `UIViewController` property and WWDC24 covers "navigation *and*
  presentations", so this is expected to work. If the modal morph misbehaves,
  the fallback is to push the viewer inside a hidden-bar `UINavigationController`.
  Highest-priority device check.
- **S2 — interactive dismiss vs. inner zoom/pan.** When zoomed in, the system
  drag-to-dismiss must defer to scroll-view panning; verify a zoomed-in image
  pans without dismissing and dismisses only at min zoom.
- **S3 — aspect mismatch.** Feed thumbnails are aspect-fill (cropped); the full
  image is aspect-fit (letterboxed). A slight morph mismatch is expected and
  acceptable (Photos has the same); confirm it reads well.
- **S4 — scroll-to-reveal timing.** Confirm the synchronous scroll-then-resolve
  inside the provider lands the cell before the dismiss morph commits (feed,
  Person Posts, Activity), and degrades to fade when the id is gone.

## Build sequence (build-green at each step)

1. Core seam (`zoomSource` plumbing, viewer branch, Reduce-Motion gate) +
   `MarkdownBodyView.zoomSourceView(forImageURL:)` + the two high-confidence
   thumbnail entries (#1 feed, #2 post-detail header).
2. Body-image entries (#3 post, #4 comment, #5 person, #7 community).
3. #8 Activity + #6 Person Posts + scroll-to-reveal on the list-backed surfaces
   (#1, #6, #8).
4. Unit tests for the resolvers + scroll-to-reveal mapping; then the simulator
   mechanics pass.

## Device verification checklist (human pass)

- [ ] Tap a feed thumbnail → image expands from the thumbnail.
- [ ] Drag the open image down → it shrinks back into the feed thumbnail;
      release low to dismiss, release high to spring back.
- [ ] Repeat from a post-detail header image.
- [ ] Open a feed thumbnail, scroll the feed far under it, dismiss → the feed
      scrolls the source back on screen and the image shrinks into it
      (scroll-to-reveal); when the post is gone from the feed, it cleanly fades.
- [ ] Tap a body image inside a post, a comment, and a profile description →
      expands and shrinks back to that inline image; scrolled-away → fade.
- [ ] Repeat from the Person "Posts" tab and from Activity.
- [ ] Zoom into an open image, drag → it pans (does not dismiss); zoom back out,
      drag → it dismisses.
- [ ] Enable Reduce Motion → presentation is the instant/cross-dissolve
      fallback, no zoom.
- [ ] Tap an image-classified web link → still opens (cross-dissolve), no
      regression.
- [ ] iPad split view: open from each column; verify present/dismiss and the
      collapsed-column → fade case.
- [ ] Multi-image post (if any) → paging works; dismiss targets the current
      page's source or fades.
- [ ] VoiceOver: focus lands on the image on present and returns to the source
      on dismiss.
