# Media Viewer Zoom Transition (v2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the full-screen media viewer expand from, and shrink back into, the tapped image using the native iOS 18 zoom transition, at every entry point, with graceful fade fallback and scroll-to-reveal on list-backed surfaces.

**Architecture:** One optional re-resolving `zoomSource: ((MediaItem) -> UIView?)?` closure threaded through `presentMediaViewer` into `MediaViewerViewController`, which switches to `preferredTransition = .zoom` when it is present (and Reduce Motion is off). Each call site supplies a closure that re-resolves its live on-screen source view by a stable id; a `nil` return degrades to the existing cross-dissolve. List-backed call sites additionally scroll the source on screen before resolving.

**Tech Stack:** Swift 6, UIKit, `UIViewController.Transition.zoom` (iOS 18.0+), `UITableViewDiffableDataSource`, Swift Testing.

## Global Constraints

- Deployment target iOS 18.0 — `.zoom` is always available; no availability guards needed.
- Swift 6 language mode + `SWIFT_STRICT_CONCURRENCY = complete` on every target touched (Spud, SpudMarkdownKit). Closures crossing into UIKit are `@MainActor`.
- No emojis in code, comments, docs, or commit messages.
- Conventional commit subjects (`feat:`, `fix:`, `refactor:`, `test:`, `docs:`).
- `SpudMarkdownKit` must not import the app target; its lookup takes only a `URL`.
- After adding/removing a source file, run `make project` (XcodeGen) before building — the generated `.xcodeproj` is gitignored.
- Build/test destination: booted reference sim by id. Resolve with `scripts/resolve-test-destination.sh`; unit target verify uses `-only-testing:` on the `Spud` test plan with `-skipPackagePluginValidation -skipMacroValidation`.
- Run `mint run swiftformat <changed paths>` BEFORE the final verify of each task, never after.
- Reduce Motion (`UIAccessibility.isReduceMotionEnabled`) must skip the zoom path entirely.
- `MediaViewerTransition` (the cross-dissolve) is KEPT as the fallback — do not delete it.
- Worktree: `/Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/media-zoom`, branch `feat/media-zoom-v2`. Read/Edit/Write WORKTREE-rooted paths, never the main-checkout absolute path.

---

## File Structure

- `Spud/Utils/UIViewController+MediaViewer.swift` — add `zoomSource` param to the shared entry point (modify).
- `Spud/Scenes/MediaViewer/MediaViewerViewController.swift` — store provider, branch transition mode at init, gate custom pan on `usesZoomTransition` (modify).
- `SpudMarkdownKit/Rendering/ImageBlockView.swift` — `zoomSourceView(forImageURL:)` on the block (modify).
- `SpudMarkdownKit/Rendering/MarkdownBodyView.swift` — public `zoomSourceView(forImageURL:)` tree walk (modify).
- `Spud/Utils/ListZoomSource.swift` — small shared helper: resolve (and optionally scroll-to-reveal) a `UITableViewDiffableDataSource` cell's thumbnail by `serverPostId` (create).
- `Spud/Scenes/PostList/PostListViewController.swift` — feed resolver + call-site wiring (modify).
- `Spud/Scenes/PostDetail/Content/PostDetailViewController.swift` — header + body + comment resolvers (modify).
- `Spud/Scenes/Person/Content/PersonViewController.swift` — profile-body + Posts-tab resolvers (modify).
- `Spud/Scenes/Community/Content/CommunityViewController.swift` — profile-body resolver (modify).
- `Spud/Scenes/Activity/ActivityViewController.swift` — post-image resolver (modify).
- `SpudMarkdownKitTests/MarkdownBodyViewZoomSourceTests.swift` — body-lookup tests (create).
- `SpudTests/ListZoomSourceTests.swift` — id→indexPath / scroll-to-reveal mapping tests (create).

---

## Task 1: Core seam — `zoomSource` plumbing + viewer transition branch

**Files:**
- Modify: `Spud/Scenes/MediaViewer/MediaViewerViewController.swift` (init ~201, make ~221, setupGestures ~383)
- Modify: `Spud/Utils/UIViewController+MediaViewer.swift`

**Interfaces:**
- Consumes: existing `MediaItem` (`Equatable`, has `imageUrl: URL`), `MediaViewerViewController.Dependencies`.
- Produces:
  - `MediaViewerViewController.init(items:startIndex:dependencies:zoomSource:)` where `zoomSource: ((MediaItem) -> UIView?)? = nil`
  - `MediaViewerViewController.make(items:startIndex:dependencies:zoomSource:)` (same trailing param)
  - `UIViewController.presentMediaViewer(imageUrl:thumbnailUrl:preloadedImage:altText:isNsfw:dependencies:zoomSource:)` where `zoomSource: ((MediaItem) -> UIView?)? = nil`

- [ ] **Step 1: Add the stored flag and thread `zoomSource` through `init`.**

In `MediaViewerViewController`, add near the other stored props (after `private var currentIndex: Int`):

```swift
    /// Whether this presentation uses the iOS 18 zoom transition (expand from /
    /// shrink back to a source view). When true the system drives the
    /// interactive dismiss, so the viewer's own swipe-down-to-dismiss pan is not
    /// installed. When false the viewer keeps its custom cross-dissolve + pan.
    private let usesZoomTransition: Bool
```

Replace `init(items:startIndex:dependencies:)` (currently ~201) with:

```swift
    init(
        items: [MediaItem],
        startIndex: Int,
        dependencies: Dependencies,
        zoomSource: ((MediaItem) -> UIView?)? = nil
    ) {
        precondition(!items.isEmpty, "MediaViewer requires at least one item")
        self.items = items
        currentIndex = min(max(0, startIndex), items.count - 1)
        imageService = dependencies.imageService

        // Honour Reduce Motion by skipping the zoom and using the cross-dissolve
        // fallback, which already collapses to an instant cut under Reduce Motion.
        let zoomSource = UIAccessibility.isReduceMotionEnabled ? nil : zoomSource
        usesZoomTransition = zoomSource != nil

        super.init(nibName: nil, bundle: nil)

        modalPresentationCapturesStatusBarAppearance = true

        if let zoomSource {
            // The system re-invokes this on present and dismiss; read the live
            // `currentIndex` so a paged-to image dismisses back to its own source
            // (or fades when that page has no on-screen source).
            preferredTransition = .zoom { [weak self] _ in
                guard let self else { return nil }
                return zoomSource(items[currentIndex])
            }
        } else {
            modalPresentationStyle = .custom
            transitioningDelegate = self
        }
    }
```

(Note: the previous init set `modalPresentationStyle = .custom` / `transitioningDelegate = self` unconditionally and had `modalPresentationCapturesStatusBarAppearance = true` — preserve that line in both branches as shown.)

- [ ] **Step 2: Thread `zoomSource` through `make`.**

Replace `static func make(items:startIndex:dependencies:)` (~221):

```swift
    static func make(
        items: [MediaItem],
        startIndex: Int = 0,
        dependencies: Dependencies,
        zoomSource: ((MediaItem) -> UIView?)? = nil
    ) -> MediaViewerViewController {
        MediaViewerViewController(
            items: items,
            startIndex: startIndex,
            dependencies: dependencies,
            zoomSource: zoomSource
        )
    }
```

- [ ] **Step 3: Gate the custom pan in `setupGestures`.**

In `setupGestures()` (~383), immediately before the `let pan = UIPanGestureRecognizer(...)` block, insert:

```swift
        // In zoom mode the system provides the interactive drag-to-shrink
        // dismiss, so installing our own swipe-down pan would fight it. Only the
        // cross-dissolve fallback needs the custom pan.
        guard !usesZoomTransition else { return }
```

- [ ] **Step 4: Add `zoomSource` to the shared entry point.**

In `Spud/Utils/UIViewController+MediaViewer.swift`, extend the doc comment and signature. Replace the function with:

```swift
    /// Presents the full-screen, zoomable media viewer for a single image.
    /// Shared by the post detail, feed, person, community, and activity screens.
    /// `MediaViewerViewController.Dependencies` is `HasImageService`; callers
    /// pass their own `dependencies.own`.
    ///
    /// `zoomSource`, when provided, opts the presentation into the iOS 18 zoom
    /// transition: the viewer expands from, and shrinks back into, the view the
    /// closure returns. The closure is re-invoked on present *and* dismiss, so it
    /// must re-resolve the live on-screen source view by a stable identifier
    /// rather than capture a `UIView` (reused cells move). Returning `nil` (the
    /// source scrolled off / was recycled) falls back to a plain cross-dissolve
    /// instead of animating from a stale frame.
    func presentMediaViewer(
        imageUrl: URL,
        thumbnailUrl: URL?,
        preloadedImage: UIImage?,
        altText: String? = nil,
        isNsfw: Bool = false,
        dependencies: MediaViewerViewController.Dependencies,
        zoomSource: ((MediaItem) -> UIView?)? = nil
    ) {
        let item = MediaItem(
            imageUrl: imageUrl,
            thumbnailUrl: thumbnailUrl,
            preloadedImage: preloadedImage,
            altText: altText,
            isNsfw: isNsfw
        )
        let viewer = MediaViewerViewController.make(
            items: [item],
            dependencies: dependencies,
            zoomSource: zoomSource
        )
        FunStats.record(.imagesViewed)
        present(viewer, animated: true)
    }
```

- [ ] **Step 5: Regenerate and build.**

Run: `make project && xcodebuild -project Spud.xcodeproj -scheme Spud -destination "$(scripts/resolve-test-destination.sh)" -skipPackagePluginValidation -skipMacroValidation build`
Expected: BUILD SUCCEEDED. No call site passes `zoomSource` yet (the param defaults to `nil`), so behavior is unchanged.

- [ ] **Step 6: Format + commit.**

```bash
mint run swiftformat Spud/Scenes/MediaViewer/MediaViewerViewController.swift Spud/Utils/UIViewController+MediaViewer.swift
git add Spud/Scenes/MediaViewer/MediaViewerViewController.swift Spud/Utils/UIViewController+MediaViewer.swift
git commit -m "feat(media-viewer): add opt-in iOS 18 zoom transition seam"
```

---

## Task 2: Markdown body-image source lookup

**Files:**
- Modify: `SpudMarkdownKit/Rendering/ImageBlockView.swift`
- Modify: `SpudMarkdownKit/Rendering/MarkdownBodyView.swift`
- Create: `SpudMarkdownKitTests/MarkdownBodyViewZoomSourceTests.swift`

**Interfaces:**
- Consumes: `ImageBlockView` (has `url: URL`, `isLoaded: Bool`, `box: UIView`), `MarkdownBodyView` (has a `stack` container of rendered block views).
- Produces:
  - `ImageBlockView.zoomSourceView(forImageURL imageURL: URL) -> UIView?`
  - `public func MarkdownBodyView.zoomSourceView(forImageURL imageURL: URL) -> UIView?`

> If `ImageBlockView`'s loaded-image property is not named `isLoaded`/`url`/`box`, grep the file first (`grep -n 'var url\|isLoaded\|let box\|var box' SpudMarkdownKit/Rendering/ImageBlockView.swift`) and use the actual names; the guard is "this block shows a loaded image whose URL == imageURL".

- [ ] **Step 1: Write the failing test.**

Create `SpudMarkdownKitTests/MarkdownBodyViewZoomSourceTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Testing
import UIKit
@testable import SpudMarkdownKit

@MainActor
struct MarkdownBodyViewZoomSourceTests {
    private func makeBody(markdown: String) -> MarkdownBodyView {
        let view = MarkdownBodyView(context: MarkdownContext(kind: .post))
        view.setBlocks(MarkdownBlockCache.shared.blocks(for: markdown))
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 2000)
        view.layoutIfNeeded()
        return view
    }

    @Test
    func returnsNilWhenNoImageRendered() {
        let body = makeBody(markdown: "Just some **text**, no images.")
        #expect(body.zoomSourceView(forImageURL: URL(string: "https://e.com/a.jpg")!) == nil)
    }

    @Test
    func returnsNilForUnloadedOrMismatchedURL() {
        // An image block that never loaded a displayable image is not a valid
        // zoom source (only the loaded state is tappable).
        let url = URL(string: "https://e.com/pic.jpg")!
        let body = makeBody(markdown: "![alt](\(url.absoluteString))")
        // Not driven to a loaded state in a unit test → nil.
        #expect(body.zoomSourceView(forImageURL: url) == nil)
        // A URL that isn't in the body → nil regardless.
        #expect(body.zoomSourceView(forImageURL: URL(string: "https://e.com/other.jpg")!) == nil)
    }
}
```

> This locks the two `nil` contracts. The loaded-state positive path is covered by the mechanics pass (a real load is async and image-backed); the unit test asserts the guards, matching the v1 branch's test scope.

- [ ] **Step 2: Run to verify it fails.**

Run: `xcodebuild -project Spud.xcodeproj -scheme SpudMarkdownKit -only-testing:SpudMarkdownKitTests/MarkdownBodyViewZoomSourceTests -destination "$(scripts/resolve-test-destination.sh)" -skipPackagePluginValidation -skipMacroValidation test`
Expected: FAIL to compile — `zoomSourceView(forImageURL:)` does not exist yet. (Create the file, `make project`, then run.)

- [ ] **Step 3: Add the block-level lookup.**

In `SpudMarkdownKit/Rendering/ImageBlockView.swift`, after the layout/setup methods add:

```swift
    /// The view a media viewer should zoom from / back to for `imageURL`: the
    /// rounded box holding the loaded image, or nil when this block is a
    /// different image or hasn't loaded a displayable image yet. Only the loaded
    /// state is tappable, so a viewer opened from here always has a loaded box.
    func zoomSourceView(forImageURL imageURL: URL) -> UIView? {
        guard isLoaded, url == imageURL else { return nil }
        return box
    }
```

- [ ] **Step 4: Add the tree-walking lookup on the body view.**

In `SpudMarkdownKit/Rendering/MarkdownBodyView.swift`, after `setBlocks`/`indexFootnotes`, add:

```swift
    /// The on-screen view a media viewer should zoom from / back to for
    /// `imageURL`: the rounded box of the loaded body image with that URL, or
    /// nil when no such image is currently rendered (the body was rebuilt /
    /// scrolled away). A nil result lets the zoom transition fall back to a fade
    /// rather than animate from a stale frame.
    public func zoomSourceView(forImageURL imageURL: URL) -> UIView? {
        imageBlockViews(in: stack)
            .lazy
            .compactMap { $0.zoomSourceView(forImageURL: imageURL) }
            .first
    }

    private func imageBlockViews(in root: UIView) -> [ImageBlockView] {
        var result: [ImageBlockView] = []
        for sub in root.subviews {
            if let image = sub as? ImageBlockView {
                result.append(image)
            } else {
                result.append(contentsOf: imageBlockViews(in: sub))
            }
        }
        return result
    }
```

> If the container is not named `stack`, grep `MarkdownBodyView.swift` for the arranged-subviews container (`UIStackView`) and use its name.

- [ ] **Step 5: Run to verify it passes.**

Run the same command as Step 2 (after `make project`).
Expected: PASS.

- [ ] **Step 6: Format + commit.**

```bash
mint run swiftformat SpudMarkdownKit/Rendering/ImageBlockView.swift SpudMarkdownKit/Rendering/MarkdownBodyView.swift SpudMarkdownKitTests/MarkdownBodyViewZoomSourceTests.swift
git add SpudMarkdownKit/Rendering/ImageBlockView.swift SpudMarkdownKit/Rendering/MarkdownBodyView.swift SpudMarkdownKitTests/MarkdownBodyViewZoomSourceTests.swift
git commit -m "feat(markdown): resolve a body image's on-screen box by URL for zoom"
```

---

## Task 3: Feed thumbnail entry point (no scroll-to-reveal yet)

**Files:**
- Modify: `Spud/Scenes/PostList/PostListViewController.swift` (cell builder `imageTapped` ~1510, private `presentMediaViewer` wrapper ~1899)

**Interfaces:**
- Consumes: `presentMediaViewer(...zoomSource:)` (Task 1); `tableView: UITableView`; `dataSource: UITableViewDiffableDataSource<Section, Item>` with `Item.post(serverPostId: Int64)`; `PostListPostCell` whose `postContentView.thumbnailView` is the source view.
- Produces: (call-site only; nothing later tasks consume, except the pattern reused in Task 6.)

- [ ] **Step 1: Add a private resolver that finds a visible cell's thumbnail by serverPostId.**

In `PostListViewController`, add near the other private helpers:

```swift
    /// The on-screen thumbnail image view for `serverPostId`, or nil when that
    /// post's cell is not currently visible. Re-resolved live so the zoom
    /// transition targets whatever cell is showing the post now (diffable cells
    /// recycle). Scroll-to-reveal is layered on in a later step.
    private func visibleThumbnailView(forServerPostId serverPostId: Int64) -> UIView? {
        guard let indexPath = dataSource?.indexPath(for: .post(serverPostId: serverPostId)),
              let cell = tableView.cellForRow(at: indexPath) as? PostListPostCell
        else { return nil }
        return cell.postContentView.thumbnailView
    }
```

- [ ] **Step 2: Pass a `zoomSource` closure at the feed call site.**

In the cell builder's `cell.imageTapped = { ... }` (~1510), change the `presentMediaViewer(...)` call to pass the closure. The closure captures `serverPostId` (a value already in scope) and re-resolves by it:

```swift
                cell.imageTapped = { [weak self] imageUrl, thumbnailUrl, thumbnailImage in
                    guard let self else { return }
                    presentMediaViewer(
                        imageUrl: imageUrl,
                        thumbnailUrl: thumbnailUrl,
                        preloadedImage: thumbnailImage,
                        altText: row.altText,
                        isNsfw: row.isNsfw,
                        zoomSource: { [weak self] _ in
                            self?.visibleThumbnailView(forServerPostId: serverPostId)
                        }
                    )
                    if markPostsRead {
                        markReadInBackground(serverPostId: serverPostId)
                    }
                }
```

- [ ] **Step 3: Thread `zoomSource` through the private `presentMediaViewer` wrapper.**

Replace the private wrapper (~1899) so it forwards the closure:

```swift
    private func presentMediaViewer(
        imageUrl: URL,
        thumbnailUrl: URL?,
        preloadedImage: UIImage?,
        altText: String? = nil,
        isNsfw: Bool = false,
        zoomSource: ((MediaItem) -> UIView?)? = nil
    ) {
        presentMediaViewer(
            imageUrl: imageUrl,
            thumbnailUrl: thumbnailUrl,
            preloadedImage: preloadedImage,
            altText: altText,
            isNsfw: isNsfw,
            dependencies: dependencies.own,
            zoomSource: zoomSource
        )
    }
```

- [ ] **Step 4: Build.**

Run: `make project && xcodebuild -project Spud.xcodeproj -scheme Spud -destination "$(scripts/resolve-test-destination.sh)" -skipPackagePluginValidation -skipMacroValidation build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Format + commit.**

```bash
mint run swiftformat Spud/Scenes/PostList/PostListViewController.swift
git add Spud/Scenes/PostList/PostListViewController.swift
git commit -m "feat(media-viewer): zoom transition from feed thumbnails"
```

---

## Task 4: Post-detail header + body + comment entry points

**Files:**
- Modify: `Spud/Scenes/PostDetail/Content/PostDetailViewController.swift` (the header `imageTapped`, the body-image and comment-image tap paths, and the private `presentMediaViewer` wrapper if one exists there)

**Interfaces:**
- Consumes: `presentMediaViewer(...zoomSource:)`; `PostDetailHeaderCell.postImageView`; `MarkdownBodyView.zoomSourceView(forImageURL:)` (Task 2); the comment cell type and its markdown body view.
- Produces: (call-site only.)

> Before editing, grep the current tap wiring: `grep -n 'presentMediaViewer\|imageTapped\|onBodyImageTapped\|postImageView\|headerCell\|HeaderCell\|CommentCell' Spud/Scenes/PostDetail/Content/PostDetailViewController.swift`. There are four `presentMediaViewer` call sites here (header, body, one more, and a web-link case). Wire `zoomSource` on the three that have an on-screen view; leave the web-link one unchanged.

- [ ] **Step 1: Add resolvers for the header and body/comment images.**

Add to `PostDetailViewController`:

```swift
    /// The visible post-detail header's image view, or nil when the header is
    /// scrolled off screen.
    private func visibleHeaderImageView() -> UIView? {
        // The header is section 0's row 0; resolve the live cell each time.
        let indexPath = IndexPath(row: 0, section: 0)
        guard let cell = tableView.cellForRow(at: indexPath) as? PostDetailHeaderCell else {
            return nil
        }
        return cell.postImageView
    }

    /// The on-screen box for a body image (`imageURL`) in the visible header
    /// cell, or nil when the header or that image is not currently rendered.
    private func visibleHeaderBodyImageView(forImageURL imageURL: URL) -> UIView? {
        let indexPath = IndexPath(row: 0, section: 0)
        guard let cell = tableView.cellForRow(at: indexPath) as? PostDetailHeaderCell else {
            return nil
        }
        return cell.bodyView?.zoomSourceView(forImageURL: imageURL)
    }
```

> Replace `IndexPath(row: 0, section: 0)` and `cell.bodyView` with the real header index and the header cell's `MarkdownBodyView` accessor once confirmed by the grep above. If the header is not a table row but a table header view, resolve `tableView.tableHeaderView` / the header container instead — the contract is "the live header's image view / body box, or nil".

- [ ] **Step 2: Add a comment-body resolver keyed by comment id.**

```swift
    /// The on-screen box for a body image (`imageURL`) inside the visible
    /// comment cell for `commentServerId`, or nil when that comment is not
    /// currently on screen (recycled / scrolled away).
    private func visibleCommentBodyImageView(
        commentServerId: Int64,
        forImageURL imageURL: URL
    ) -> UIView? {
        guard let indexPath = dataSource?.indexPath(for: .comment(serverId: commentServerId)),
              let cell = tableView.cellForRow(at: indexPath) as? PostDetailCommentCell
        else { return nil }
        return cell.bodyView?.zoomSourceView(forImageURL: imageURL)
    }
```

> Use the actual diffable `Item` case for a comment and the actual comment-cell type + body accessor (from the grep). If comments are not diffable-item-backed, resolve via the comment's row lookup the VC already uses elsewhere.

- [ ] **Step 3: Pass `zoomSource` at the three call sites.**

- Header image tap → `zoomSource: { [weak self] _ in self?.visibleHeaderImageView() }`
- Post body image tap → `zoomSource: { [weak self] item in self?.visibleHeaderBodyImageView(forImageURL: item.imageUrl) }`
- Comment body image tap (closure has the comment's server id in scope) → `zoomSource: { [weak self] item in self?.visibleCommentBodyImageView(commentServerId: commentServerId, forImageURL: item.imageUrl) }`
- Web-link image case → leave unchanged (no `zoomSource`).

Thread `zoomSource` through the VC's private `presentMediaViewer` wrapper if it has one (same shape as Task 3 Step 3); otherwise pass `dependencies: ...` + `zoomSource:` directly.

- [ ] **Step 4: Build.**

Run: `make project && xcodebuild -project Spud.xcodeproj -scheme Spud -destination "$(scripts/resolve-test-destination.sh)" -skipPackagePluginValidation -skipMacroValidation build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Format + commit.**

```bash
mint run swiftformat Spud/Scenes/PostDetail/Content/PostDetailViewController.swift
git add Spud/Scenes/PostDetail/Content/PostDetailViewController.swift
git commit -m "feat(media-viewer): zoom transition for post-detail header, body, and comment images"
```

---

## Task 5: Person + Community profile body images

**Files:**
- Modify: `Spud/Scenes/Person/Content/PersonViewController.swift` (the `headerView.onBodyImageTapped` path ~239)
- Modify: `Spud/Scenes/Community/Content/CommunityViewController.swift` (the `headerView.onBodyImageTapped` path ~182)

**Interfaces:**
- Consumes: `presentMediaViewer(...zoomSource:)`; each screen's persistent header view exposing its `MarkdownBodyView` (grep for `bodyView`/`descriptionView` on `PersonHeaderView` / `CommunityHeaderView`).
- Produces: (call-site only.)

> The profile headers are persistent (not recycled), so the resolver is a direct lookup on the retained header view. Grep first: `grep -n 'onBodyImageTapped\|bodyView\|var headerView\|MarkdownBodyView' Spud/Scenes/Person/Content/PersonViewController.swift Spud/Scenes/Person/Content/PersonHeaderView.swift Spud/Scenes/Community/Content/CommunityViewController.swift Spud/Scenes/Community/Content/CommunityHeaderView.swift`.

- [ ] **Step 1: Person — pass a body resolver.**

At the `headerView.onBodyImageTapped = { [weak self] url, altText, _ in ... }` call site, pass:

```swift
                        zoomSource: { [weak self] item in
                            self?.headerView.bodyView?.zoomSourceView(forImageURL: item.imageUrl)
                        }
```

(Use the real header accessor from the grep; `headerView` is retained by the VC.)

- [ ] **Step 2: Community — pass a body resolver.**

Same shape at `CommunityViewController`'s `headerView.onBodyImageTapped`.

- [ ] **Step 3: Build.**

Run: `make project && xcodebuild -project Spud.xcodeproj -scheme Spud -destination "$(scripts/resolve-test-destination.sh)" -skipPackagePluginValidation -skipMacroValidation build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Format + commit.**

```bash
mint run swiftformat Spud/Scenes/Person/Content/PersonViewController.swift Spud/Scenes/Community/Content/CommunityViewController.swift
git add Spud/Scenes/Person/Content/PersonViewController.swift Spud/Scenes/Community/Content/CommunityViewController.swift
git commit -m "feat(media-viewer): zoom transition for person and community profile body images"
```

---

## Task 6: Shared list scroll-to-reveal helper + feed/Activity/Person-Posts adoption

**Files:**
- Create: `Spud/Utils/ListZoomSource.swift`
- Create: `SpudTests/ListZoomSourceTests.swift`
- Modify: `Spud/Scenes/PostList/PostListViewController.swift` (use helper in `visibleThumbnailView`)
- Modify: `Spud/Scenes/Person/Content/PersonViewController.swift` (Posts-tab cell resolver)
- Modify: `Spud/Scenes/Activity/ActivityViewController.swift` (post-image resolver)

**Interfaces:**
- Consumes: `UITableViewDiffableDataSource`, `UITableView`.
- Produces:
  - `func listZoomSource<S: Hashable, I: Hashable>(tableView:dataSource:item:thumbnail:) -> UIView?` — resolves the item's cell, scrolling it on screen (non-animated) if off-screen, then returns `thumbnail(cell)`; nil when the item is absent from the snapshot. Generic over the diffable section/item types and cell type via the `thumbnail` closure. (Signature finalized in Step 3.)

- [ ] **Step 1: Write the failing test for the id→indexPath mapping + absent-id nil.**

Create `SpudTests/ListZoomSourceTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Testing
import UIKit
@testable import Spud

@MainActor
struct ListZoomSourceTests {
    private enum Section: Hashable { case main }

    private func makeTable(items: [Int]) -> (UITableView, UITableViewDiffableDataSource<Section, Int>) {
        let table = UITableView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        table.register(UITableViewCell.self, forCellReuseIdentifier: "c")
        let ds = UITableViewDiffableDataSource<Section, Int>(tableView: table) { tv, ip, _ in
            tv.dequeueReusableCell(withIdentifier: "c", for: ip)
        }
        var snap = NSDiffableDataSourceSnapshot<Section, Int>()
        snap.appendSections([.main])
        snap.appendItems(items)
        ds.apply(snap, animatingDifferences: false)
        table.layoutIfNeeded()
        return (table, ds)
    }

    @Test
    func returnsNilForItemAbsentFromSnapshot() {
        let (table, ds) = makeTable(items: [1, 2, 3])
        let result = listZoomSource(tableView: table, dataSource: ds, item: 999) { $0.contentView }
        #expect(result == nil)
    }

    @Test
    func resolvesContentViewForPresentItem() {
        let (table, ds) = makeTable(items: [1, 2, 3])
        let result = listZoomSource(tableView: table, dataSource: ds, item: 1) { $0.contentView }
        #expect(result != nil)
    }

    @Test
    func scrollsAnOffscreenItemOnScreenThenResolves() {
        // 200 rows in a 480pt table: item 190 starts far below the fold.
        let (table, ds) = makeTable(items: Array(0..<200))
        let before = table.indexPathsForVisibleRows ?? []
        #expect(!before.contains(IndexPath(row: 190, section: 0)))
        let result = listZoomSource(tableView: table, dataSource: ds, item: 190) { $0.contentView }
        #expect(result != nil)
        #expect(table.indexPathsForVisibleRows?.contains(IndexPath(row: 190, section: 0)) == true)
    }
}
```

- [ ] **Step 2: Run to verify it fails.**

Run: `make project && xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud -only-testing:SpudTests/ListZoomSourceTests -destination "$(scripts/resolve-test-destination.sh)" -skipPackagePluginValidation -skipMacroValidation test`
Expected: FAIL to compile — `listZoomSource` undefined.

- [ ] **Step 3: Implement the helper.**

Create `Spud/Utils/ListZoomSource.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// Resolves the live zoom-source view for a diffable list item, scrolling the
/// item on screen first when it is currently off screen.
///
/// Used by the media viewer's `zoomSource` closures on list-backed surfaces
/// (feed, Person "Posts", Activity): on dismiss the zoom transition asks for the
/// source view, and if the user scrolled the originating cell out of sight we
/// bring it back — non-animated, so the reveal does not compound with the zoom —
/// then hand back its thumbnail. Returns nil when `item` is no longer in the
/// snapshot (e.g. the feed refreshed the post away), which degrades the
/// transition to a plain fade.
@MainActor
func listZoomSource<Section: Hashable, Item: Hashable>(
    tableView: UITableView,
    dataSource: UITableViewDiffableDataSource<Section, Item>,
    item: Item,
    thumbnail: (UITableViewCell) -> UIView?
) -> UIView? {
    guard let indexPath = dataSource.indexPath(for: item) else { return nil }
    if tableView.cellForRow(at: indexPath) == nil {
        // Off screen: bring it on, synchronously, before the morph commits.
        tableView.scrollToRow(at: indexPath, at: .none, animated: false)
        tableView.layoutIfNeeded()
    }
    guard let cell = tableView.cellForRow(at: indexPath) else { return nil }
    return thumbnail(cell)
}
```

- [ ] **Step 4: Run to verify it passes.**

Run the same command as Step 2.
Expected: PASS (3 tests).

- [ ] **Step 5: Route the feed resolver through the helper.**

In `PostListViewController.visibleThumbnailView(forServerPostId:)` (from Task 3), replace the body with:

```swift
    private func visibleThumbnailView(forServerPostId serverPostId: Int64) -> UIView? {
        guard let dataSource else { return nil }
        return listZoomSource(
            tableView: tableView,
            dataSource: dataSource,
            item: .post(serverPostId: serverPostId)
        ) { ($0 as? PostListPostCell)?.postContentView.thumbnailView }
    }
```

- [ ] **Step 6: Wire the Person "Posts" tab and Activity call sites.**

- Person Posts tab: at `cell.imageTapped = { ... }` (~813), pass a `zoomSource` that routes through `listZoomSource` against the Posts-tab table + its diffable data source, keyed by the post's server id (grep the tab's data source + item case + cell type first). If the Posts tab embeds a `PostListViewController`, prefer delegating to that child's own resolver rather than duplicating.
- Activity: at `container.postContentView.imageTapped = { ... }` (~543), same — route through `listZoomSource` against Activity's table + data source, keyed by the post's server id, returning the content view's thumbnail.

Both must build; both degrade to nil (fade) when the item is gone.

- [ ] **Step 7: Build + run the resolver tests.**

Run: `make project && xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud -only-testing:SpudTests/ListZoomSourceTests -only-testing:SpudMarkdownKitTests/MarkdownBodyViewZoomSourceTests -destination "$(scripts/resolve-test-destination.sh)" -skipPackagePluginValidation -skipMacroValidation test`
Expected: BUILD SUCCEEDED, all tests PASS.

- [ ] **Step 8: Format + commit.**

```bash
mint run swiftformat Spud/Utils/ListZoomSource.swift SpudTests/ListZoomSourceTests.swift Spud/Scenes/PostList/PostListViewController.swift Spud/Scenes/Person/Content/PersonViewController.swift Spud/Scenes/Activity/ActivityViewController.swift
git add Spud/Utils/ListZoomSource.swift SpudTests/ListZoomSourceTests.swift Spud/Scenes/PostList/PostListViewController.swift Spud/Scenes/Person/Content/PersonViewController.swift Spud/Scenes/Activity/ActivityViewController.swift
git commit -m "feat(media-viewer): scroll-to-reveal source on dismiss for list-backed surfaces"
```

---

## Task 7: Full verification + docs

**Files:**
- Modify: `docs/features/` — the media-viewer / image-viewing capability doc + README index (grep `docs/features` for the existing media/image doc; update behavior + add a Given/When/Then scenario for the zoom transition and its fade/scroll-to-reveal fallbacks).

- [ ] **Step 1: Full unit-test gate.**

Run: `make test-only ONLY=SpudTests` then `make test-only ONLY=SpudMarkdownKitTests` (each resolves the destination and runs the plan target).
Expected: both green (`✔ Test run with N tests ... passed`).

- [ ] **Step 2: Snapshot sanity.**

Run: `make snapshot`
Expected: green — this change adds a transition, touches no snapshot-rendered layout, so refs must be unchanged. If any snapshot differs, STOP and investigate (an unintended layout change).

- [ ] **Step 3: Update feature docs.**

Update the media/image-viewing capability doc: note the zoom expand/shrink transition, the Reduce-Motion + off-screen fade fallbacks, and scroll-to-reveal on feed/Posts/Activity. Add a Given/When/Then scenario. Update both README index sections (capability table + coverage-by-area map).

- [ ] **Step 4: Commit docs.**

```bash
git add docs/features/
git commit -m "docs: media viewer zoom transition behavior"
```

- [ ] **Step 5: Simulator mechanics pass (agent, then hand to human for feel).**

The simulator cannot confirm interactive feel, but it can confirm mechanics. With the reference sim booted, drive: open a feed image (present morph plays), dismiss (shrink), scroll the feed far and dismiss (scroll-to-reveal), enable Reduce Motion and confirm the fade, open a body image and dismiss. Capture screen recordings. Anything interactive (drag-to-shrink, frame rate, zoomed-in pan-vs-dismiss) is deferred to the human device pass using the spec's checklist.

---

## Self-Review

**Spec coverage:**
- Core seam (`zoomSource`, viewer branch, Reduce-Motion gate) → Task 1. ✓
- `MarkdownBodyView.zoomSourceView` → Task 2. ✓
- Feed (#1) → Task 3; scroll-to-reveal for it → Task 6. ✓
- Post-detail header/body/comment (#2–#4) → Task 4. ✓
- Person/Community body (#5, #7) → Task 5. ✓
- Person Posts (#6) + Activity (#8) + scroll-to-reveal → Task 6. ✓
- Web-link (#9) keeps fade → explicitly untouched in Task 4. ✓
- Accessibility (Reduce Motion) → Task 1 gate; VoiceOver focus → Task 7 device checklist. ✓
- iPad split view → Task 7 device checklist. ✓
- Graceful `nil`→fade degradation → every resolver returns nil off-screen. ✓
- Testing (unit + mechanics + device) → Tasks 2, 6, 7. ✓

**Placeholder scan:** grep-first notes are deliberate (the plan gives the exact shape and the fallback contract; the grep confirms today's property names in files that churn). No "TBD"/"add error handling"/"similar to". Code shown at every code step.

**Type consistency:** `zoomSource: ((MediaItem) -> UIView?)?` identical across Tasks 1/3/4/5/6. `zoomSourceView(forImageURL:)` identical in Task 2 and its consumers. `listZoomSource(tableView:dataSource:item:thumbnail:)` defined in Task 6 Step 3, consumed in Steps 5–6. `visibleThumbnailView(forServerPostId:)` defined Task 3, rewritten Task 6.
