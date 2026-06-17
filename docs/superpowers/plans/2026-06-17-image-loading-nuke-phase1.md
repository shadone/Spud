# Image-loading performance — Phase 1 (Nuke foundation swap) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `ImageService`'s four `NSCache`s and hand-rolled `URLSession` fetch/decode with a single configured Nuke `ImagePipeline`, behind the unchanged `ImageServiceType`/`AsyncStream` surface — delivering a persistent disk cache (warm relaunch), correct memory accounting + pressure eviction, and TTFP signposts.

**Architecture:** `ImageService` becomes a thin adapter over a Nuke `ImagePipeline` built by a new `ImagePipelineFactory`. The protocol, all ~18 call sites, and the `StaticImageService` snapshot fake are untouched. Progressive decode (Phase 2) and tuning (Phase 3) are separate plans.

**Tech Stack:** Swift 6 (SpudDataKit is Swift 6 language mode), Nuke 13.x (SPM, remote), ImageIO/UIKit, GRDB-adjacent (no DB work here), XCTest, swift-snapshot-testing (unchanged).

## Global Constraints

- **Nuke version:** pin `kean/Nuke` `from: "13.0.0"` (iOS 15+; app targets iOS 18 SDK). Verbatim SPM url `https://github.com/kean/Nuke`.
- **Swift 6 strict concurrency:** SpudDataKit is Swift 6 language mode — code must compile clean; if Nuke 13 emits Sendable warnings, use `@preconcurrency import Nuke` (try plain `import Nuke` first).
- **Public API frozen:** `ImageServiceType` and `ImageLoadingState` must not change. No call site edits. `StaticImageService` fake untouched.
- **Per-process disk cache:** each process gets its own `DataCache(name:)` in its own caches dir. NO shared App-Group cache.
- **Preserve behaviors:** custom `AppUserAgent` User-Agent header; non-2xx diagnostic logging (status + Cloudflare/server headers — body snippet intentionally dropped, see Task 3); error → `AlertService`; cancellation → quiet exit (no alert, no `.failure`); `imageSize(for:)` layout reservation; animated GIF playback + original-bytes save/share.
- **Build flags:** headless `xcodebuild` and `build_and_test.py` keep `-skipPackagePluginValidation -skipMacroValidation`. Build/test on `iPhone 17` sim for SpudDataKit (framework scheme needs `--simulator`). Snapshot suite runs on iPhone 14 Pro / portrait.
- **No emojis** in code, comments, commits. Conventional commit subjects. Commit per task.
- **Branch:** all work on `feat/image-loading-nuke` (created off `main` before Task 1).

---

### Task 1: Add Nuke as an SPM dependency

**Files:**
- Modify: `project.yml` (XcodeGen `packages:` + SpudDataKit target `dependencies:`)
- Regenerate: `Spud.xcodeproj` via `make project`

**Interfaces:**
- Produces: `import Nuke` available in SpudDataKit and SpudDataKitTests.

- [ ] **Step 1: Add the remote package to `project.yml`**

Under the top-level `packages:` map (add the key if absent), add:

```yaml
packages:
  Nuke:
    url: https://github.com/kean/Nuke
    from: 13.0.0
```

- [ ] **Step 2: Declare the dependency on the SpudDataKit target**

In `project.yml`, under `targets: SpudDataKit: dependencies:`, add a `package` entry (Nuke's primary product is the `Nuke` library):

```yaml
    dependencies:
      - package: Nuke
        product: Nuke
```

Add the same under `targets: SpudDataKitTests: dependencies:` so tests can `import Nuke`.

- [ ] **Step 3: Regenerate the project and resolve packages**

Run:
```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud
make project
xcodebuild -resolvePackageDependencies -project Spud.xcodeproj
```
Expected: XcodeGen regenerates; package resolution pins Nuke 13.x into `Package.resolved` (alongside local LemmyKit and openapi-* deps).

- [ ] **Step 4: Verify it builds and `import Nuke` works**

Add a temporary file `SpudDataKit/Services/Image/_NukeImportCheck.swift`:
```swift
import Nuke
private let _nukeImportCheck: ImagePipeline.Type = ImagePipeline.self
```
Run:
```bash
python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme SpudDataKit --simulator "iPhone 17"
```
Expected: `Build: SUCCESS`. If Nuke emits Sendable/concurrency warnings on `import Nuke`, change the import to `@preconcurrency import Nuke` in the check file and rebuild.

- [ ] **Step 5: Remove the temporary check file and commit**

```bash
rm SpudDataKit/Services/Image/_NukeImportCheck.swift
git add project.yml Spud.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
git commit -m "chore: add Nuke 13 as SPM dependency for SpudDataKit"
```
Note: `Spud.xcodeproj` itself is gitignored/generated; only `Package.resolved` is tracked. Use `git status -uall` to confirm what is staged.

---

### Task 2: ImagePipeline factory — URLSession config + pipeline assembly

**Files:**
- Create: `SpudDataKit/Services/Image/ImagePipelineFactory.swift`
- Test: `SpudDataKitTests/ImagePipelineFactoryTests.swift`

**Interfaces:**
- Produces:
  - `enum ImagePipelineFactory` with
    - `static func makeURLSessionConfiguration() -> URLSessionConfiguration` (UA header set)
    - `static func makePipeline(cacheName: String) -> ImagePipeline`
    - `static func logUnacceptableResponse(_ response: URLResponse)` (validate-time diagnostic)

- [ ] **Step 1: Write the failing test for the User-Agent header**

`SpudDataKitTests/ImagePipelineFactoryTests.swift`:
```swift
import XCTest
@testable import SpudDataKit

final class ImagePipelineFactoryTests: XCTestCase {
    func test_urlSessionConfiguration_carriesAppUserAgent() {
        let config = ImagePipelineFactory.makeURLSessionConfiguration()
        let ua = config.httpAdditionalHeaders?["User-Agent"] as? String
        XCTAssertEqual(ua, AppUserAgent.value)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run:
```bash
python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme SpudDataKit --simulator "iPhone 17"
```
Expected: FAIL — `ImagePipelineFactory` is not defined (compile error).

- [ ] **Step 3: Implement the factory**

`SpudDataKit/Services/Image/ImagePipelineFactory.swift`:
```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Nuke
import OSLog

private let logger = Logger.imageService

/// Builds the Nuke `ImagePipeline` that backs `ImageService`: a custom-User-Agent
/// data loader, a per-process disk cache, and a memory cache that evicts under
/// pressure. One pipeline per process (no shared App-Group cache).
enum ImagePipelineFactory {
    /// Session config matching the old `ImageService` session: a plain
    /// `Spud/<version>` User-Agent so instances whose nginx denylists the default
    /// `CFNetwork/...` token still serve images. See `AppUserAgent`.
    static func makeURLSessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        var headers = configuration.httpAdditionalHeaders ?? [:]
        headers["User-Agent"] = AppUserAgent.value
        configuration.httpAdditionalHeaders = headers
        return configuration
    }

    /// Logs the status and the headers that reveal who rejected an image request
    /// (Cloudflare edge vs Lemmy vs pict-rs). The response body snippet the old
    /// `logFailedResponse` printed is intentionally dropped: Nuke's data loader
    /// validates the response before the body is buffered, and keeping the body
    /// would require a bespoke `URLSessionDataDelegate` loader that also defeats
    /// the incremental delivery Phase 2's progressive decode relies on.
    static func logUnacceptableResponse(_ response: URLResponse) {
        guard let http = response as? HTTPURLResponse,
              !(200 ... 299).contains(http.statusCode)
        else { return }
        func header(_ name: String) -> String {
            (http.value(forHTTPHeaderField: name)) ?? "-"
        }
        logger.error(
            """
            Image load failed status=\(http.statusCode, privacy: .public) \
            url=\(http.url?.absoluteString ?? "-", privacy: .public)
            server=\(header("Server"), privacy: .public) \
            cf-ray=\(header("CF-Ray"), privacy: .public) \
            cf-mitigated=\(header("cf-mitigated"), privacy: .public) \
            content-type=\(header("Content-Type"), privacy: .public) \
            retry-after=\(header("Retry-After"), privacy: .public)
            """
        )
    }

    static func makePipeline(cacheName: String) -> ImagePipeline {
        let dataLoader = DataLoader(
            configuration: makeURLSessionConfiguration(),
            validate: { response in
                if let error = DataLoader.validate(response: response) {
                    logUnacceptableResponse(response)
                    return error
                }
                return nil
            }
        )

        // Per-process disk cache. If the cache dir can't be created, run without
        // a disk cache rather than crashing image loading.
        let dataCache = try? DataCache(name: cacheName)
        dataCache?.sizeLimit = 200 * 1024 * 1024

        return ImagePipeline { config in
            config.dataLoader = dataLoader
            config.dataCache = dataCache
            // Store both the processed (downsampled) thumbnail and the original,
            // so a warm relaunch reads the small thumbnail straight off disk.
            config.dataCachePolicy = .storeAll
            // Native decompression on the decode thread (replaces the old manual
            // `byPreparingForDisplay()`), keeping scroll hitch-free.
            config.isUsingPrepareForDisplay = true
        }
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme SpudDataKit --simulator "iPhone 17"
```
Expected: `test_urlSessionConfiguration_carriesAppUserAgent` PASSES. If `import Nuke` warns under Swift 6, switch to `@preconcurrency import Nuke`.

- [ ] **Step 5: Commit**

```bash
git add SpudDataKit/Services/Image/ImagePipelineFactory.swift SpudDataKitTests/ImagePipelineFactoryTests.swift
git commit -m "feat: add ImagePipelineFactory (UA loader, disk cache, prepare-for-display)"
```

---

### Task 3: Pure error/state mapping helpers

**Files:**
- Modify: `SpudDataKit/Services/Image/ImageService.swift` (add a private mapping extension; replace the existing `Error.isImageLoadingCancellation`)
- Test: `SpudDataKitTests/ImageServiceMappingTests.swift`

**Interfaces:**
- Produces:
  - `func imageLoadingError(from nukeError: ImagePipeline.Error) -> ImageLoadingError`
  - `Error.isImageLoadingCancellation: Bool` extended to recognize `ImagePipeline.Error.cancelled`

- [ ] **Step 1: Write the failing tests**

`SpudDataKitTests/ImageServiceMappingTests.swift`:
```swift
import Nuke
import XCTest
@testable import SpudDataKit

final class ImageServiceMappingTests: XCTestCase {
    func test_pipelineCancelled_isCancellation() {
        let error: Error = ImagePipeline.Error.cancelled
        XCTAssertTrue(error.isImageLoadingCancellation)
    }

    func test_swiftCancellation_isCancellation() {
        let error: Error = CancellationError()
        XCTAssertTrue(error.isImageLoadingCancellation)
    }

    func test_dataLoadingFailure_isNotCancellation() {
        let underlying = URLError(.timedOut)
        let error: Error = ImagePipeline.Error.dataLoadingFailed(error: underlying)
        XCTAssertFalse(error.isImageLoadingCancellation)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run:
```bash
python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme SpudDataKit --simulator "iPhone 17"
```
Expected: FAIL — `ImagePipeline.Error.cancelled` not yet recognized by `isImageLoadingCancellation` (test_pipelineCancelled fails).

- [ ] **Step 3: Replace the cancellation helper and add the error mapper**

In `SpudDataKit/Services/Image/ImageService.swift`, replace the existing `private extension Error { … isImageLoadingCancellation … }` with:
```swift
private extension Error {
    /// Whether this error represents a cancelled image request rather than a real
    /// transport failure: a Swift task cancellation, `URLError.cancelled`
    /// (`NSURLErrorCancelled`, -999), `ImagePipeline.Error.cancelled`, or any of
    /// those wrapped in `ImageLoadingError.network`.
    var isImageLoadingCancellation: Bool {
        if self is CancellationError { return true }
        if (self as? URLError)?.code == .cancelled { return true }
        if let nukeError = self as? ImagePipeline.Error, case .cancelled = nukeError { return true }
        if let imageError = self as? ImageLoadingError, case let .network(underlying) = imageError {
            return underlying.isImageLoadingCancellation
        }
        return false
    }
}

private extension ImageService {
    /// Maps a Nuke pipeline error onto the app's `ImageLoadingError` so callers
    /// (and `AlertService`) see the same error vocabulary they did before Nuke.
    func imageLoadingError(from nukeError: ImagePipeline.Error) -> ImageLoadingError {
        switch nukeError {
        case .dataLoadingFailed(let error):
            return .network(error)
        case .decodingFailed, .decoderNotRegistered, .dataIsEmpty:
            return .cannotDecode
        default:
            return .network(nukeError)
        }
    }
}
```
Add `import Nuke` (or `@preconcurrency import Nuke`) to the file's imports.

- [ ] **Step 4: Run to verify it passes**

Run the same `build_and_test.py` command.
Expected: all three mapping tests PASS.

- [ ] **Step 5: Commit**

```bash
git add SpudDataKit/Services/Image/ImageService.swift SpudDataKitTests/ImageServiceMappingTests.swift
git commit -m "feat: map Nuke pipeline errors and recognize Nuke cancellation"
```

---

### Task 4: Swap `fetch(_:downsampleTo:)` onto the pipeline (with injectable pipeline)

**Files:**
- Modify: `SpudDataKit/Services/Image/ImageService.swift` (init, stored props, `fetch(_:downsampleTo:)`)
- Test: `SpudDataKitTests/ImageServiceDownsampleTests.swift`

**Interfaces:**
- Consumes: `ImagePipelineFactory.makePipeline(cacheName:)`, `imageLoadingError(from:)`.
- Produces:
  - `ImageService.init(alertService:pipeline:)` (internal, injectable) and public `convenience init(alertService:)`.
  - A reusable `DataLoading` test stub `StubDataLoader` in the test target.

- [ ] **Step 1: Write the failing test with a stub data loader**

`SpudDataKitTests/ImageServiceDownsampleTests.swift`:
```swift
import Nuke
import UIKit
import XCTest
@testable import SpudDataKit

/// A Nuke `DataLoading` stub that returns canned bytes (or an error) synchronously.
final class StubDataLoader: DataLoading, @unchecked Sendable {
    let result: Result<(Data, URLResponse), Error>
    init(result: Result<(Data, URLResponse), Error>) { self.result = result }

    func loadData(
        with request: URLRequest,
        didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
        completion: @escaping @Sendable (Error?) -> Void
    ) -> any Cancellable {
        switch result {
        case let .success((data, response)):
            didReceiveData(data, response)
            completion(nil)
        case let .failure(error):
            completion(error)
        }
        return StubCancellable()
    }
}

struct StubCancellable: Nuke.Cancellable { func cancel() {} }

enum ImageFixture {
    /// A 8x8 red PNG, valid for decoding.
    static func pngData() -> Data {
        let size = CGSize(width: 8, height: 8)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        return image.pngData()!
    }

    static func httpResponse(_ url: URL, status: Int = 200) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
    }
}

final class ImageServiceDownsampleTests: XCTestCase {
    private func makeService(loader: DataLoading) -> ImageService {
        let pipeline = ImagePipeline { config in
            config.dataLoader = loader
            config.imageCache = nil
        }
        return ImageService(alertService: AlertService(), pipeline: pipeline)
    }

    func test_downsample_yieldsReadyImage() async {
        let url = URL(string: "https://example.com/a.png")!
        let loader = StubDataLoader(result: .success((ImageFixture.pngData(), ImageFixture.httpResponse(url))))
        let service = makeService(loader: loader)

        var lastImage: UIImage?
        for await state in service.fetch(url, downsampleTo: CGSize(width: 64, height: 64)) {
            if case let .ready(image) = state { lastImage = image }
        }
        XCTAssertNotNil(lastImage)
    }
}
```
(If `AlertService()` needs arguments, construct it as the existing snapshot fakes do — see `ImageService` snapshot setup in the project's other tests.)

- [ ] **Step 2: Run to verify it fails**

Run `build_and_test.py` (SpudDataKit, iPhone 17).
Expected: FAIL — `ImageService.init(alertService:pipeline:)` does not exist (compile error).

- [ ] **Step 3: Rework `ImageService` init + `fetch(_:downsampleTo:)`**

In `ImageService.swift`:
1. Delete the four `NSCache` stored properties and their setup in `init`, and delete the `session` property.
2. Add:
```swift
    private let pipeline: ImagePipeline

    /// Name for this process's on-disk image cache. Each process (app, widget,
    /// extension) gets its own directory; we do not share an App-Group cache
    /// because Nuke's DataCache is not multi-process-write safe.
    private static let diskCacheName = "info.ddenis.Spud.images"

    init(alertService: AlertServiceType, pipeline: ImagePipeline) {
        self.alertService = alertService
        self.pipeline = pipeline
    }

    public convenience init(alertService: AlertServiceType) {
        self.init(
            alertService: alertService,
            pipeline: ImagePipelineFactory.makePipeline(cacheName: Self.diskCacheName)
        )
    }
```
3. Replace `fetch(_:downsampleTo:)` with:
```swift
    public func fetch(_ url: URL, downsampleTo pointSize: CGSize) -> AsyncStream<ImageLoadingState> {
        let request = ImageRequest(
            url: url,
            processors: [ImageProcessors.Resize(size: pointSize, unit: .points, contentMode: .aspectFit)]
        )
        return makeStream(for: request, url: url)
    }

    /// Shared adapter: drives a Nuke request to the `AsyncStream` event model.
    /// Yields `.loading(thumbnail:)` immediately, then `.ready` on success or
    /// `.failure` on a real error. A cancelled request exits quietly.
    private func makeStream(for request: ImageRequest, url: URL) -> AsyncStream<ImageLoadingState> {
        AsyncStream { continuation in
            let task = Task { [weak self] in
                guard let self else { continuation.finish(); return }
                continuation.yield(.loading(thumbnail: nil))
                do {
                    let image = try await pipeline.image(for: request)
                    if Task.isCancelled { continuation.finish(); return }
                    recordImageSize(image.size, for: url)
                    continuation.yield(.ready(image))
                } catch {
                    if Task.isCancelled || error.isImageLoadingCancellation {
                        continuation.finish(); return
                    }
                    let mapped = (error as? ImagePipeline.Error).map(imageLoadingError(from:)) ?? .network(error)
                    alertService.image(error: mapped, for: url)
                    continuation.yield(.failure)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
```
4. Remove the now-unused `loadDownsampledImage`, `loadImage`, `data(from:)`, `logFailedResponse` methods (the diagnostic moved to `ImagePipelineFactory.logUnacceptableResponse`). Keep `knownImageSizes`, `recordImageSize`, `imageSize(for:)`.

- [ ] **Step 4: Run to verify it passes**

Run `build_and_test.py` (SpudDataKit, iPhone 17).
Expected: `test_downsample_yieldsReadyImage` PASSES. Fix any remaining references to the deleted methods until the framework compiles.

- [ ] **Step 5: Commit**

```bash
git add SpudDataKit/Services/Image/ImageService.swift SpudDataKitTests/ImageServiceDownsampleTests.swift
git commit -m "feat: back fetch(downsampleTo:) with Nuke ImagePipeline"
```

---

### Task 5: Swap `fetch(_:thumbnail:)` onto the pipeline

**Files:**
- Modify: `SpudDataKit/Services/Image/ImageService.swift` (`fetch(_:thumbnail:)`)
- Test: `SpudDataKitTests/ImageServiceFullFetchTests.swift`

**Interfaces:**
- Consumes: `makeStream(for:url:)`, the `StubDataLoader`/`ImageFixture` from Task 4's test file.

- [ ] **Step 1: Write the failing test**

`SpudDataKitTests/ImageServiceFullFetchTests.swift`:
```swift
import Nuke
import UIKit
import XCTest
@testable import SpudDataKit

final class ImageServiceFullFetchTests: XCTestCase {
    func test_fullFetch_yieldsReadyImage() async {
        let url = URL(string: "https://example.com/full.png")!
        let pipeline = ImagePipeline { config in
            config.dataLoader = StubDataLoader(
                result: .success((ImageFixture.pngData(), ImageFixture.httpResponse(url)))
            )
            config.imageCache = nil
        }
        let service = ImageService(alertService: AlertService(), pipeline: pipeline)

        var lastImage: UIImage?
        for await state in service.fetch(url, thumbnail: nil) {
            if case let .ready(image) = state { lastImage = image }
        }
        XCTAssertNotNil(lastImage)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run `build_and_test.py`. Expected: FAIL — `fetch(_:thumbnail:)` still references deleted code or the seeded-thumbnail path isn't wired (compile error or no `.ready`).

- [ ] **Step 3: Reimplement `fetch(_:thumbnail:)`**

```swift
    public func fetch(_ url: URL, thumbnail thumbnailUrl: URL?) -> AsyncStream<ImageLoadingState> {
        // Phase 1: a plain full-image fetch. The Phase-2 progressive-decode plan
        // adds incremental previews here; the old hand-rolled thumbnail race is
        // retired in favor of Nuke's memory cache + (later) progressive scans.
        let request = ImageRequest(url: url)
        return makeStream(for: request, url: url)
    }
```

- [ ] **Step 4: Run to verify it passes**

Run `build_and_test.py`. Expected: `test_fullFetch_yieldsReadyImage` PASSES.

- [ ] **Step 5: Commit**

```bash
git add SpudDataKit/Services/Image/ImageService.swift SpudDataKitTests/ImageServiceFullFetchTests.swift
git commit -m "feat: back fetch(url:thumbnail:) with Nuke ImagePipeline"
```

---

### Task 6: Swap animated path (`fetchAnimatedImage`, `animatedImageData`) onto the pipeline

**Files:**
- Modify: `SpudDataKit/Services/Image/ImageService.swift`
- Test: `SpudDataKitTests/ImageServiceAnimatedTests.swift`

**Interfaces:**
- Consumes: `pipeline.data(for:)`, existing `AnimatedImageDecoder.animatedImage(from:)`, `makeStream(for:url:)`.

- [ ] **Step 1: Write the failing test for `animatedImageData`**

`SpudDataKitTests/ImageServiceAnimatedTests.swift`:
```swift
import Nuke
import XCTest
@testable import SpudDataKit

final class ImageServiceAnimatedTests: XCTestCase {
    func test_animatedImageData_returnsOriginalBytes() async {
        let url = URL(string: "https://example.com/a.gif")!
        let bytes = ImageFixture.pngData() // any non-empty bytes; we assert round-trip
        let pipeline = ImagePipeline { config in
            config.dataLoader = StubDataLoader(result: .success((bytes, ImageFixture.httpResponse(url))))
            config.imageCache = nil
        }
        let service = ImageService(alertService: AlertService(), pipeline: pipeline)

        let result = await service.animatedImageData(url)
        XCTAssertEqual(result, bytes)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run `build_and_test.py`. Expected: FAIL — `animatedImageData` still references the deleted `data(from:)`/`animatedDataCache` (compile error).

- [ ] **Step 3: Reimplement the animated path**

```swift
    public func fetchAnimatedImage(_ url: URL) -> AsyncStream<ImageLoadingState> {
        AsyncStream { continuation in
            let task = Task { [weak self] in
                guard let self else { continuation.finish(); return }
                continuation.yield(.loading(thumbnail: nil))
                do {
                    let (data, _) = try await pipeline.data(for: ImageRequest(url: url))
                    if Task.isCancelled { continuation.finish(); return }
                    if let animated = AnimatedImageDecoder.animatedImage(from: data) {
                        recordImageSize(animated.size, for: url)
                        continuation.yield(.ready(animated))
                    } else if let image = UIImage(data: data) {
                        let decoded = await image.byPreparingForDisplay() ?? image
                        recordImageSize(decoded.size, for: url)
                        continuation.yield(.ready(decoded))
                    } else {
                        alertService.image(error: .cannotDecode, for: url)
                        continuation.yield(.failure)
                    }
                } catch {
                    if Task.isCancelled || error.isImageLoadingCancellation {
                        continuation.finish(); return
                    }
                    let mapped = (error as? ImagePipeline.Error).map(imageLoadingError(from:)) ?? .network(error)
                    alertService.image(error: mapped, for: url)
                    continuation.yield(.failure)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func animatedImageData(_ url: URL) async -> Data? {
        do {
            let (data, _) = try await pipeline.data(for: ImageRequest(url: url))
            return data
        } catch {
            return nil
        }
    }
```

- [ ] **Step 4: Run to verify it passes**

Run `build_and_test.py`. Expected: `test_animatedImageData_returnsOriginalBytes` PASSES and the framework compiles (all four `NSCache`s and old load methods now gone).

- [ ] **Step 5: Commit**

```bash
git add SpudDataKit/Services/Image/ImageService.swift SpudDataKitTests/ImageServiceAnimatedTests.swift
git commit -m "feat: back animated image path with Nuke data(for:)"
```

---

### Task 7: Error + cancellation behavior end-to-end

**Files:**
- Test: `SpudDataKitTests/ImageServiceErrorBehaviorTests.swift`
- Modify (only if needed): `SpudDataKit/Services/Image/ImageService.swift`

**Interfaces:**
- Consumes: `StubDataLoader`, `ImageFixture`, a spy `AlertService`.

- [ ] **Step 1: Write the failing tests**

`SpudDataKitTests/ImageServiceErrorBehaviorTests.swift`:
```swift
import Nuke
import XCTest
@testable import SpudDataKit

/// Records image errors so tests can assert whether the service alerted.
final class SpyAlertService: AlertServiceType, @unchecked Sendable {
    private(set) var imageErrors: [URL] = []
    func image(error: ImageLoadingError, for url: URL) { imageErrors.append(url) }
    // Implement any other AlertServiceType requirements as no-ops, mirroring the
    // existing test fake used by snapshot tests.
}

final class ImageServiceErrorBehaviorTests: XCTestCase {
    func test_transportFailure_yieldsFailure_andAlerts() async {
        let url = URL(string: "https://example.com/x.png")!
        let alert = SpyAlertService()
        let pipeline = ImagePipeline { config in
            config.dataLoader = StubDataLoader(result: .failure(URLError(.timedOut)))
            config.imageCache = nil
        }
        let service = ImageService(alertService: alert, pipeline: pipeline)

        var sawFailure = false
        for await state in service.fetch(url, downsampleTo: CGSize(width: 64, height: 64)) {
            if case .failure = state { sawFailure = true }
        }
        XCTAssertTrue(sawFailure)
        XCTAssertEqual(alert.imageErrors, [url])
    }
}
```
(Match `SpyAlertService` to the real `AlertServiceType` surface — copy the no-op stubs from the existing snapshot-test fake.)

- [ ] **Step 2: Run to verify it fails or passes**

Run `build_and_test.py`. Expected: compiles; the test passes if Tasks 3-4 wired error mapping correctly. If it fails, fix the mapping in `makeStream` until green.

- [ ] **Step 3: (If needed) adjust `makeStream` error path**

No code change expected. If the alert is not recorded, confirm `imageLoadingError(from:)` is reached and `alertService.image(error:for:)` is called on the non-cancellation branch.

- [ ] **Step 4: Run to verify it passes**

Run `build_and_test.py`. Expected: `test_transportFailure_yieldsFailure_andAlerts` PASSES.

- [ ] **Step 5: Commit**

```bash
git add SpudDataKitTests/ImageServiceErrorBehaviorTests.swift
git commit -m "test: transport failure yields .failure and alerts"
```

---

### Task 8: TTFP / decode signposts

**Files:**
- Create: `SpudDataKit/Services/Image/ImageLoadingSignposter.swift`
- Modify: `SpudDataKit/Services/Image/ImageService.swift` (wrap `makeStream` work in signpost intervals)

**Interfaces:**
- Produces: `struct ImageLoadingSignposter` with `func beginInterval(_ name: StaticString, url: URL) -> OSSignpostIntervalState` and `func endInterval(_ name: StaticString, _ state: OSSignpostIntervalState)` (thin wrapper over `OSSignposter`).

- [ ] **Step 1: Add the signposter**

`SpudDataKit/Services/Image/ImageLoadingSignposter.swift`:
```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import OSLog

/// Lightweight os_signpost wrapper for measuring image time-to-first-pixel and
/// decode in Instruments. Always-on (signposts are production-safe and cheap).
struct ImageLoadingSignposter: Sendable {
    private let signposter = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "info.ddenis.Spud",
        category: "ImageLoading"
    )

    func interval<T>(_ name: StaticString, url: URL, _ work: () async throws -> T) async rethrows -> T {
        let state = signposter.beginInterval(name, id: signposter.makeSignpostID())
        defer { signposter.endInterval(name, state) }
        return try await work()
    }
}
```

- [ ] **Step 2: Wrap the pipeline load in `makeStream`**

In `ImageService`, add `private let signposter = ImageLoadingSignposter()` and wrap the load:
```swift
                    let image = try await signposter.interval("fetch", url: url) {
                        try await self.pipeline.image(for: request)
                    }
```
Apply the same wrapping to the `pipeline.data(for:)` call in `fetchAnimatedImage` with name `"fetchAnimated"`.

- [ ] **Step 3: Build to verify it compiles**

Run `build_and_test.py` (SpudDataKit, iPhone 17). Expected: `Build: SUCCESS`, all existing tests still PASS. (Signposts are behavior-free; no new unit test.)

- [ ] **Step 4: Commit**

```bash
git add SpudDataKit/Services/Image/ImageLoadingSignposter.swift SpudDataKit/Services/Image/ImageService.swift
git commit -m "feat: add image-loading signposts for TTFP/decode"
```

---

### Task 9: Remove dead code and verify the full app + snapshot suite

**Files:**
- Delete: `SpudDataKit/Services/Image/ImageDownsampler.swift`, `SpudDataKitTests/ImageDownsamplerTests.swift` (only if no remaining references)
- Modify: `project.yml` only if the deleted files are explicitly listed (XcodeGen usually globs)

**Interfaces:** none.

- [ ] **Step 1: Confirm `ImageDownsampler` has no remaining consumers**

Run:
```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud
grep -rn "ImageDownsampler" --include="*.swift" .
```
Expected: only its own file + test. If anything else references it, STOP and keep the file.

- [ ] **Step 2: Delete the dead files and regenerate**

```bash
rm SpudDataKit/Services/Image/ImageDownsampler.swift SpudDataKitTests/ImageDownsamplerTests.swift
make project
```

- [ ] **Step 3: Build + run the SpudDataKit unit tests**

```bash
python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme SpudDataKit --simulator "iPhone 17"
```
Expected: `Build: SUCCESS`, all ImageService tests PASS.

- [ ] **Step 4: Build the app scheme and run the snapshot suite (visual parity gate)**

```bash
xcodebuild -project Spud.xcodeproj -scheme Spud \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -skipPackagePluginValidation -skipMacroValidation build

xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan SpudSnapshots \
  -destination 'platform=iOS Simulator,name=iPhone 14 Pro' \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: app builds; snapshot suite PASSES. The snapshot fake (`StaticImageService`) is untouched, so any failure indicates a real-image rendering path regression (e.g. the resize `contentMode` differs from the old downsampler) — adjust the `ImageProcessors.Resize` params (e.g. `.aspectFill`) until parity returns.

- [ ] **Step 5: Commit**

```bash
git add -u
git commit -m "refactor: remove dead ImageDownsampler after Nuke swap"
```

---

## Self-Review

**Spec coverage:**
- Disk cache → Task 2 (`DataCache`, `.storeAll`). ✓
- Memory fix + pressure eviction → Tasks 2/4 (Nuke `ImageCache` replaces the buggy `NSCache` cost accounting; old caches deleted). ✓
- Per-process cache decision → Task 4 (`diskCacheName`, per-process). ✓
- Custom UA → Task 2. ✓
- Non-2xx diagnostic (headers; body snippet dropped, documented) → Task 2. ✓
- Error → AlertService, cancellation quiet exit → Tasks 3/7. ✓
- `imageSize(for:)` preserved → Task 4 (kept `knownImageSizes`/`recordImageSize`). ✓
- Animated playback + save/share bytes → Task 6. ✓
- Signposts (Phase 1) → Task 8. ✓
- Protocol/fake unchanged, snapshot gate → Task 9. ✓
- Progressive decode is explicitly Phase 2 (placeholder note in Task 5), not in this plan. ✓

**Placeholder scan:** No "TBD"/"add error handling"/vague steps; every code step shows code. The `SpyAlertService`/`AlertService` construction references the existing snapshot fake — flagged inline to copy its no-op stubs (the real `AlertServiceType` surface lives in the codebase and must be matched exactly).

**Type consistency:** `makeStream(for:url:)`, `imageLoadingError(from:)`, `isImageLoadingCancellation`, `ImagePipelineFactory.makePipeline(cacheName:)`, `ImageService.init(alertService:pipeline:)`, `StubDataLoader`, `ImageFixture` are defined once and reused with consistent signatures across tasks.

## Open verification points (resolve during execution, not blockers)

- Exact `AlertServiceType` surface for `SpyAlertService`/`AlertService()` construction — copy from the existing snapshot fake.
- Whether `import Nuke` needs `@preconcurrency` under Swift 6 (Task 1 Step 4 decides).
- `ImageProcessors.Resize` `contentMode` parity with the old downsampler — the snapshot suite (Task 9) is the gate.
