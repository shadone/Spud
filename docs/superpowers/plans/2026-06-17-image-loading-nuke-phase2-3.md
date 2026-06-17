# Image-loading performance — Phase 2 (progressive decode) & Phase 3 (prefetch) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add progressive (incremental) decode so the full-size viewer and post-detail header paint coarse-to-sharp before the full download finishes (Phase 2), and move the feed's thumbnail prefetch onto Nuke's low-priority `ImagePrefetcher` so warm-up no longer competes with visible-cell loads (Phase 3).

**Architecture:** Both build on the Phase-1 `ImageService`→Nuke `ImagePipeline` adapter, behind the unchanged `ImageServiceType`. Phase 2 switches `fetch(url:thumbnail:)` from `pipeline.image(for:)` to the streaming `pipeline.imageTask(with:).events` API and enables progressive decoding on the pipeline. Phase 3 adds two prefetch methods to `ImageServiceType` (default no-op), backs them with an `ImagePrefetcher`, and rewires `PostListViewController`'s prefetch hooks.

**Tech Stack:** Swift 6 (SpudDataKit Swift 6 language mode; Spud app target), Nuke 13.x, XCTest.

## Global Constraints

- **Nuke 13** already added (Phase 1). Plain `import Nuke` (no `@preconcurrency`).
- **Public API additions only:** `ImageServiceType` gains `startPrefetching`/`stopPrefetching` with **default no-op** protocol-extension implementations, so existing call sites and all snapshot fakes (`StaticImageService`/`ScriptedImageService`/`StubImageService`) are unaffected. No existing method signature changes.
- **Event model unchanged:** every fetch stream still yields `.loading(thumbnail:)` first, then `.ready`/`.failure`, then finishes. Cancellation → quiet exit (no `alertService`, no `.failure`).
- **Error mapping** stays `ImageService.imageLoadingError(from:)` (static); cancellation recognized via `Error.isImageLoadingCancellation` (already handles `ImagePipeline.Error.cancelled`).
- **Build flags:** headless `xcodebuild`/`build_and_test.py` keep `-skipPackagePluginValidation -skipMacroValidation`; SpudDataKit framework scheme needs `--simulator "iPhone 17"`.
- **No emojis**; conventional commit subjects; commit per task. `git status -uall`; stage explicit paths only (never `git add -A`); never stage `.remember/remember.md`, dirty `__Snapshots__` PNGs, or anything under `.claude/worktrees/`.
- **Branch:** `feat/image-loading-nuke-phase2` (already created off `main`).
- **Verified Nuke 13 API (use exactly):**
  - `pipeline.imageTask(with: ImageRequest) -> ImageTask` (creating + iterating `.events` starts the load).
  - `imageTask.events: AsyncStream<ImageTask.Event>`; `Event` cases: `.started`, `.progress(Progress)`, `.preview(ImageResponse)`, `.finished(Result<ImageResponse, ImagePipeline.Error>)`.
  - `ImageResponse.image -> UIImage`.
  - `imageTask.cancel()`.
  - `config.isProgressiveDecodingEnabled: Bool`.
  - `ImagePrefetcher(pipeline: ImagePipeline, destination: .memoryCache, maxConcurrentRequestCount: Int = 2)`; `startPrefetching(with: [ImageRequest])`, `stopPrefetching(with: [ImageRequest])` (and `[URL]` variants). Prefetcher requests run at low priority automatically.

---

### Task 1: Enable progressive decode + stream `fetch(url:thumbnail:)` via ImageTask.events

**Files:**
- Modify: `SpudDataKit/Services/Image/ImagePipelineFactory.swift` (enable progressive decoding)
- Modify: `SpudDataKit/Services/Image/ImageLoadingSignposter.swift` (add begin/end interval pair)
- Modify: `SpudDataKit/Services/Image/ImageService.swift` (`fetch(url:thumbnail:)` → progressive event stream; add `makeProgressiveStream`)
- Test: `SpudDataKitTests/ImageServiceFullFetchTests.swift` (extend)

**Interfaces:**
- Consumes: `ImageService.imageLoadingError(from:)`, `Error.isImageLoadingCancellation`, the memory-cache seed `pipeline.cache[ImageRequest(url:)]?.image`, `StubDataLoader`/`ImageFixture` (from `ImageServiceDownsampleTests.swift`).
- Produces: `makeProgressiveStream(for:url:initialThumbnail:)`; `ImageLoadingSignposter.beginInterval(_:)`/`endInterval(_:_:)`.

- [ ] **Step 1: Enable progressive decoding in the factory**

In `ImagePipelineFactory.makePipeline`, inside the `ImagePipeline { config in ... }` closure, add:
```swift
            // Progressive JPEGs paint coarse->sharp via ImageTask previews
            // (consumed by ImageService.makeProgressiveStream for the viewer /
            // post-detail header). Non-progressive sources simply emit no previews.
            config.isProgressiveDecodingEnabled = true
```

- [ ] **Step 2: Add a begin/end interval pair to the signposter**

`ImageLoadingSignposter` currently only has the closure wrapper `interval(_:_:)`. The progressive path yields intermediate values during the load, so it needs explicit begin/end. Add:
```swift
    func beginInterval(_ name: StaticString) -> OSSignpostIntervalState {
        signposter.beginInterval(name, id: signposter.makeSignpostID())
    }

    func endInterval(_ name: StaticString, _ state: OSSignpostIntervalState) {
        signposter.endInterval(name, state)
    }
```

- [ ] **Step 3: Write the failing tests**

Extend `SpudDataKitTests/ImageServiceFullFetchTests.swift` with two tests that drive the new event-based path (a single-chunk stub yields no `.preview`, so these assert the final + failure behavior through the new code):
```swift
    func test_fullFetch_failure_yieldsFailureAndAlerts() async {
        let url = URL(string: "https://example.com/bad.png")!
        let alert = SpyAlertService()
        let pipeline = ImagePipeline { config in
            config.dataLoader = StubDataLoader(result: .failure(URLError(.timedOut)))
            config.imageCache = nil
        }
        let service = ImageService(alertService: alert, pipeline: pipeline)

        var sawFailure = false
        for await state in service.fetch(url, thumbnail: nil) {
            if case .failure = state { sawFailure = true }
        }
        XCTAssertTrue(sawFailure)
        XCTAssertEqual(alert.imageErrors, [url])
    }

    func test_fullFetch_throughEventStream_yieldsReady() async {
        let url = URL(string: "https://example.com/full.png")!
        let pipeline = ImagePipeline { config in
            config.dataLoader = StubDataLoader(result: .success((ImageFixture.pngData(), ImageFixture.httpResponse(url))))
            config.imageCache = nil
        }
        let service = ImageService(alertService: AlertService(), pipeline: pipeline)

        var lastImage: UIImage?
        for await state in service.fetch(url, thumbnail: nil) {
            if case let .ready(image) = state { lastImage = image }
        }
        XCTAssertNotNil(lastImage)
    }
```
(`SpyAlertService` lives in `ImageServiceErrorBehaviorTests.swift`; if not visible to this file in the same target it already is — both are in `SpudDataKitTests`.)

- [ ] **Step 4: Run to verify it fails**

Run: `python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme SpudDataKit --simulator "iPhone 17"`
Expected: the existing `fetch(url:thumbnail:)` (using `makeStream`) likely still passes `test_fullFetch_throughEventStream_yieldsReady`, but you are about to re-implement it; treat RED as "the progressive path does not yet exist". If both pass against the old `makeStream` path, proceed to Step 5 and confirm they still pass after the rewrite (the rewrite must not regress them).

- [ ] **Step 5: Rewrite `fetch(url:thumbnail:)` to the progressive event stream**

Replace the Phase-1 `fetch(_:thumbnail:)` body so it routes to a new `makeProgressiveStream` (keep the synchronous memory-cache seed):
```swift
    public func fetch(_ url: URL, thumbnail thumbnailUrl: URL?) -> AsyncStream<ImageLoadingState> {
        let seeded = thumbnailUrl.flatMap { pipeline.cache[ImageRequest(url: $0)]?.image }
        return makeProgressiveStream(for: ImageRequest(url: url), url: url, initialThumbnail: seeded)
    }

    /// Drives a Nuke `ImageTask` to the `AsyncStream` event model, surfacing
    /// progressive-decode previews as `.loading(thumbnail:)` so the viewer and
    /// post-detail header paint coarse->sharp before the full image arrives.
    /// Non-progressive sources emit no previews and fall through to `.ready`.
    private func makeProgressiveStream(
        for request: ImageRequest,
        url: URL,
        initialThumbnail: UIImage?
    ) -> AsyncStream<ImageLoadingState> {
        AsyncStream { continuation in
            let imageTask = pipeline.imageTask(with: request)
            let consumer = Task { [weak self] in
                guard let self else { continuation.finish(); return }
                continuation.yield(.loading(thumbnail: initialThumbnail))
                let signpost = signposter.beginInterval("fetchFull")
                defer { signposter.endInterval("fetchFull", signpost) }
                for await event in imageTask.events {
                    if Task.isCancelled { break }
                    switch event {
                    case let .preview(response):
                        continuation.yield(.loading(thumbnail: response.image))
                    case let .finished(.success(response)):
                        recordImageSize(response.image.size, for: url)
                        continuation.yield(.ready(response.image))
                    case let .finished(.failure(error)):
                        if Task.isCancelled || error.isImageLoadingCancellation { break }
                        alertService.image(error: ImageService.imageLoadingError(from: error), for: url)
                        continuation.yield(.failure)
                    case .started, .progress:
                        break
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                imageTask.cancel()
                consumer.cancel()
            }
        }
    }
```
(Leave `makeStream` in place — `fetch(downsampleTo:)` still uses it.)

- [ ] **Step 6: Run to verify it passes**

Run the `build_and_test.py` command. Expected: both new tests PASS plus the existing `test_fullFetch_seedsThumbnailFromMemoryCache` (the seed is preserved). Full SpudDataKit suite green.

- [ ] **Step 7: Commit**

```bash
git add SpudDataKit/Services/Image/ImagePipelineFactory.swift SpudDataKit/Services/Image/ImageLoadingSignposter.swift SpudDataKit/Services/Image/ImageService.swift SpudDataKitTests/ImageServiceFullFetchTests.swift
git commit -m "feat: progressive decode for full-image fetch via ImageTask.events"
```

---

### Task 2: Add prefetch to `ImageServiceType`, backed by `ImagePrefetcher`

**Files:**
- Modify: `SpudDataKit/Services/Image/ImageServiceType.swift` (protocol methods + default no-op)
- Modify: `SpudDataKit/Services/Image/ImageService.swift` (prefetcher + shared `downsampleRequest` helper + implementations)
- Test: `SpudDataKitTests/ImageServicePrefetchTests.swift` (new)

**Interfaces:**
- Produces:
  - `ImageServiceType.startPrefetching(_ urls: [URL], downsampleTo pointSize: CGSize)` and `stopPrefetching(_ urls: [URL], downsampleTo pointSize: CGSize)` (default no-op).
  - `ImageService.downsampleRequest(url:pointSize:) -> ImageRequest` (static, internal) — the single source of truth for the feed downsample request, used by both `fetch(downsampleTo:)` and prefetch so they warm the same cache entry.

- [ ] **Step 1: Add the protocol methods with default no-ops**

In `ImageServiceType.swift`, add to the protocol:
```swift
    /// Begin low-priority warm-up of feed thumbnails at the given downsample
    /// size, so a cell that scrolls into view finds the decoded image cached.
    func startPrefetching(_ urls: [URL], downsampleTo pointSize: CGSize)

    /// Cancel warm-up started by `startPrefetching` for rows that scrolled out
    /// of the prefetch window.
    func stopPrefetching(_ urls: [URL], downsampleTo pointSize: CGSize)
```
And to the `public extension ImageServiceType` default block:
```swift
    /// Default: no prefetching. Real implementations override this.
    func startPrefetching(_ urls: [URL], downsampleTo pointSize: CGSize) {}

    func stopPrefetching(_ urls: [URL], downsampleTo pointSize: CGSize) {}
```

- [ ] **Step 2: Write the failing test**

`SpudDataKitTests/ImageServicePrefetchTests.swift`:
```swift
import Nuke
import UIKit
import XCTest
@testable import SpudDataKit

final class ImageServicePrefetchTests: XCTestCase {
    func test_downsampleRequest_matchesFetchTarget() {
        let url = URL(string: "https://example.com/x.png")!
        let size = CGSize(width: 64, height: 64)
        let request = ImageService.downsampleRequest(url: url, pointSize: size)
        XCTAssertEqual(request.url, url)
        XCTAssertEqual(request.processors.count, 1, "exactly the resize processor")
    }

    func test_prefetch_callsAreSafe() {
        let url = URL(string: "https://example.com/y.png")!
        let pipeline = ImagePipeline { config in
            config.dataLoader = StubDataLoader(result: .success((ImageFixture.pngData(), ImageFixture.httpResponse(url))))
            config.imageCache = nil
        }
        let service = ImageService(alertService: AlertService(), pipeline: pipeline)
        // Smoke test: start then stop must not crash and must be no-throw.
        service.startPrefetching([url], downsampleTo: CGSize(width: 64, height: 64))
        service.stopPrefetching([url], downsampleTo: CGSize(width: 64, height: 64))
    }
}
```

- [ ] **Step 3: Run to verify it fails**

Run `build_and_test.py`. Expected: FAIL — `ImageService.downsampleRequest` and the prefetch implementations don't exist.

- [ ] **Step 4: Extract the shared request + implement prefetch**

In `ImageService.swift`:
1. Add a stored prefetcher built from the same pipeline:
```swift
    private let prefetcher: ImagePrefetcher
```
   In the internal designated `init(alertService:pipeline:)`, after `self.pipeline = pipeline`:
```swift
        self.prefetcher = ImagePrefetcher(pipeline: pipeline, destination: .memoryCache)
```
2. Add the shared request helper and refactor `fetch(downsampleTo:)` to use it:
```swift
    /// The Nuke request the feed uses for a downsampled thumbnail. Single source
    /// of truth so prefetch warms exactly the cache entry the cell later reads.
    static func downsampleRequest(url: URL, pointSize: CGSize) -> ImageRequest {
        ImageRequest(
            url: url,
            processors: [ImageProcessors.Resize(size: pointSize, unit: .points, contentMode: .aspectFit)]
        )
    }
```
   Change `fetch(downsampleTo:)` to build its request via `Self.downsampleRequest(url: url, pointSize: pointSize)` (keep the rest — it still calls `makeStream(...)`).
3. Implement the prefetch methods:
```swift
    public func startPrefetching(_ urls: [URL], downsampleTo pointSize: CGSize) {
        let requests = urls.map { Self.downsampleRequest(url: $0, pointSize: pointSize) }
        prefetcher.startPrefetching(with: requests)
    }

    public func stopPrefetching(_ urls: [URL], downsampleTo pointSize: CGSize) {
        let requests = urls.map { Self.downsampleRequest(url: $0, pointSize: pointSize) }
        prefetcher.stopPrefetching(with: requests)
    }
```

- [ ] **Step 5: Run to verify it passes**

Run `build_and_test.py`. Expected: both prefetch tests PASS; full SpudDataKit suite green.

- [ ] **Step 6: Commit**

```bash
git add SpudDataKit/Services/Image/ImageServiceType.swift SpudDataKit/Services/Image/ImageService.swift SpudDataKitTests/ImageServicePrefetchTests.swift
git commit -m "feat: ImagePrefetcher-backed prefetch on ImageServiceType"
```

---

### Task 3: Rewire `PostListViewController` prefetch to the new methods

**Files:**
- Modify: `Spud/Scenes/PostList/PostListViewController.swift` (replace manual `prefetchTasks` with `imageService.startPrefetching`/`stopPrefetching`)

**Interfaces:**
- Consumes: `ImageServiceType.startPrefetching(_:downsampleTo:)`/`stopPrefetching(_:downsampleTo:)`, `PostListPostViewModel.prefetchThumbnailUrl(for:postContentDetector:)`, `PostListPostCell.thumbnailDimension`.

- [ ] **Step 1: Replace the prefetch hooks**

In `PostListViewController.swift`:
1. Delete the `prefetchTasks` dictionary property (`private var prefetchTasks: [Int64: Task<Void, Never>] = [:]`) and its doc-comment.
2. Replace `tableView(_:prefetchRowsAt:)` body so it collects the thumbnail URLs and calls the service once:
```swift
    func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
        let postContentDetector = dependencies.own.postContentDetectorService
        let urls: [URL] = indexPaths.compactMap { indexPath in
            guard case let .post(serverPostId) = dataSource.itemIdentifier(for: indexPath),
                  let row = rowsByServerPostId[serverPostId]
            else { return nil }
            return PostListPostViewModel.prefetchThumbnailUrl(for: row, postContentDetector: postContentDetector)
        }
        guard !urls.isEmpty else { return }
        let size = CGSize(width: PostListPostCell.thumbnailDimension, height: PostListPostCell.thumbnailDimension)
        imageService.startPrefetching(urls, downsampleTo: size)
    }

    func tableView(_ tableView: UITableView, cancelPrefetchingForRowsAt indexPaths: [IndexPath]) {
        let postContentDetector = dependencies.own.postContentDetectorService
        let urls: [URL] = indexPaths.compactMap { indexPath in
            guard case let .post(serverPostId) = dataSource.itemIdentifier(for: indexPath),
                  let row = rowsByServerPostId[serverPostId]
            else { return nil }
            return PostListPostViewModel.prefetchThumbnailUrl(for: row, postContentDetector: postContentDetector)
        }
        guard !urls.isEmpty else { return }
        let size = CGSize(width: PostListPostCell.thumbnailDimension, height: PostListPostCell.thumbnailDimension)
        imageService.stopPrefetching(urls, downsampleTo: size)
    }
```
3. If `prefetchTasks` was referenced anywhere else (e.g. cancelled in `deinit`/`viewDidDisappear`), remove those references — `grep -n prefetchTasks Spud/Scenes/PostList/PostListViewController.swift` must return nothing after this step.

- [ ] **Step 2: Build the full Spud app (the gate)**

Run:
```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud
xcodebuild -project Spud.xcodeproj -scheme Spud \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -skipPackagePluginValidation -skipMacroValidation build
```
Expected: BUILD SUCCEEDED. Also run the SpudDataKit unit tests once (`build_and_test.py --scheme SpudDataKit --simulator "iPhone 17"`) to confirm no regression.

- [ ] **Step 3: Commit**

```bash
git add Spud/Scenes/PostList/PostListViewController.swift
git commit -m "refactor: feed prefetch uses ImagePrefetcher via ImageService"
```

---

## Self-Review

**Spec coverage (Phase 2 & 3 sections of the design doc):**
- Phase 2 enable `isProgressiveDecodingEnabled` → Task 1 Step 1. ✓
- Phase 2 map progressive scans to `.loading(thumbnail:)`, final → `.ready`; full path only (downsample keeps `makeStream`) → Task 1 Step 5. ✓
- Phase 2 non-progressive sources degrade to seed + ready → Task 1 (no `.preview` events) + preserved memory-cache seed. ✓
- Phase 3 adopt `ImagePrefetcher` → Tasks 2-3. ✓
- Phase 3 "tune cache budgets / validate TTFP via signposts" → requires on-device Instruments profiling; NOT done headlessly. The signpost intervals (`fetchFull` begin/end added in Task 1; `fetchDownsample`/`fetchAnimated` from Phase 1) are the instrument; budget constants (disk 200 MB) are left as-is pending device data. Documented here as the remaining manual step.

**Placeholder scan:** No TBD/vague steps; every code step shows code.

**Type consistency:** `makeProgressiveStream(for:url:initialThumbnail:)`, `beginInterval(_:)`/`endInterval(_:_:)`, `downsampleRequest(url:pointSize:)`, `startPrefetching(_:downsampleTo:)`/`stopPrefetching(_:downsampleTo:)` are defined once and used consistently. `imageLoadingError(from:)` and `isImageLoadingCancellation` reused from Phase 1 unchanged.

## Open verification points (resolve during execution)
- Whether iterating `ImageTask.events` after the surrounding `Task` is cancelled needs the explicit `imageTask.cancel()` in `onTermination` (it does — included) to stop Nuke promptly. Confirm no leak by building.
- Progressive-preview emission itself is not unit-testable deterministically without a chunked progressive-JPEG stream; the unit tests cover the event→state mapping (ready/failure/seed) and progressive paint is verified on-device via the `fetchFull` signpost. Documented, not a gap.
- Prefetch warming effectiveness (cache hit on scroll) is verified on-device; unit tests cover request-shape consistency + call safety.
