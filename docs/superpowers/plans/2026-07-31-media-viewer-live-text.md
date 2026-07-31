# Media Viewer Live Text Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When an image in Spud's full-screen media viewer contains text, iOS's Live Text button appears with the viewer's chrome, letting the user select, copy, translate, look up, and share that text, and tap phone numbers, addresses, and URLs baked into the image.

**Architecture:** A single new `LiveTextController` owns one `ImageAnalysisInteraction` per image view and decides *when* to analyze. `ZoomableImageView` holds one and feeds it the final full-resolution image; `MediaViewerPageViewController` gates analysis on being the current page; `MediaViewerViewController` mirrors chrome visibility onto the button and arbitrates its own gestures against live text. VisionKit's analyzer sits behind an `ImageTextAnalyzing` seam so the decision logic is testable in the Simulator, where Live Text itself is expected to be unavailable.

**Tech Stack:** UIKit, VisionKit (`ImageAnalyzer`, `ImageAnalysisInteraction`), Swift Testing, Swift 6 language mode / complete strict concurrency.

**Spec:** `docs/superpowers/specs/2026-07-31-media-viewer-live-text-design.md`

## Global Constraints

- Deployment floor is iOS 26.0 — **do not write `#available(iOS 26, *)` guards**; VisionKit's Live Text APIs are unconditionally available.
- All new app-target code is Swift 6 language mode with complete strict concurrency. UI types here are `@MainActor`.
- `preferredInteractionTypes` is exactly `[.textSelection, .dataDetectors]`. Do not add `.imageSubject` or `.visualLookUp` — they are explicitly out of scope.
- Animated items (`MediaItem.isAnimated`) are never analyzed.
- Only the final full-resolution image is analyzed. Thumbnails and degraded previews are never analyzed.
- No emojis in code, comments, docs, or commit messages.
- Conventional commit subjects (`feat:`, `fix:`, `test:`, `docs:`).
- New Swift files require `make project` (XcodeGen) before they compile.
- Run `mint run swiftformat .` **before** the final test verify of each task, never after.
- Failures are silent by design: unsupported device, thrown analysis, cancellation, and no-text-found all degrade to "no Live Text button". No user-facing error, no `DiagnosticLog` event.

### Known testing limitation, do not fight it

`VisionKit.ImageAnalysis` has **no public initializer**, so a fake analyzer cannot fabricate one. The seam therefore returns `ImageAnalysis?` and fakes return `nil`. This is deliberate:

- Unit tests cover **when** analysis runs, when it is skipped, and when it is cancelled — all of the decision logic.
- Assigning a real analysis to the interaction, the button actually appearing, and text actually being selectable are **only** verifiable on a physical device (Task 6).

Do not invent a mock `ImageAnalysis`, do not make the seam return `Any`, and do not claim the feature works because unit tests are green.

### Build and test commands

```bash
# Regenerate the Xcode project after adding files
make project

# Run one test class
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudTests/LiveTextControllerTests \
  -destination "$(scripts/resolve-test-destination.sh)" \
  -skipPackagePluginValidation -skipMacroValidation test

# Run the whole SpudTests target
make test-only ONLY=SpudTests
```

Swift Testing results do **not** appear in xcodebuild's "Executed N tests" summary — look for `✔ Test run with N tests in M suites passed`.

---

## File Structure

**Create:**

- `Spud/Scenes/MediaViewer/ImageTextAnalyzing.swift` — the VisionKit seam protocol and its system implementation. Small and dependency-free so tests can import it without touching the controller.
- `Spud/Scenes/MediaViewer/LiveTextController.swift` — owns the `ImageAnalysisInteraction`, decides when to analyze, exposes hit-testing and button visibility.
- `SpudTests/FakeImageTextAnalyzer.swift` — recording fake used by two test classes.
- `SpudTests/LiveTextControllerTests.swift` — analysis-lifecycle tests.
- `SpudTests/ZoomableImageViewLiveTextTests.swift` — wiring and accessibility tests.
- `SpudTests/MediaViewerLiveTextGestureTests.swift` — gesture-arbitration tests.

**Modify:**

- `Spud/Scenes/MediaViewer/ZoomableImageView.swift` — hold a `LiveTextController`, feed it final images, expose hit-testing / button visibility / accessibility swap.
- `Spud/Scenes/MediaViewer/MediaViewerPageViewController.swift` — add `isCurrentPage`.
- `Spud/Scenes/MediaViewer/MediaViewerViewController.swift` — set `isCurrentPage`, mirror chrome onto the button, arbitrate gestures.
- `docs/features/media-viewer.md` and `docs/features/README.md` — feature documentation.

---

### Task 1: The VisionKit seam

**Files:**
- Create: `Spud/Scenes/MediaViewer/ImageTextAnalyzing.swift`
- Create: `SpudTests/FakeImageTextAnalyzer.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `protocol ImageTextAnalyzing` with `var isSupported: Bool { get }` and `func analyze(_ image: UIImage) async throws -> ImageAnalysis?`; `struct SystemImageTextAnalyzer: ImageTextAnalyzing`; test fake `final class FakeImageTextAnalyzer: ImageTextAnalyzing` with `var isSupported: Bool`, `private(set) var analyzeCallCount: Int`, `private(set) var cancelledCallCount: Int`, `var blocksUntilResumed: Bool`, and `func resumePendingAnalysis()`.

Note: the spec sketched `isSupported` as a `static var`. Use an **instance** property so the fake can vary it per test.

- [ ] **Step 1: Write the seam**

Create `Spud/Scenes/MediaViewer/ImageTextAnalyzing.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit
import VisionKit

/// A seam over VisionKit's `ImageAnalyzer` so the Live Text decision logic can
/// be exercised in tests and in the Simulator, where Live Text itself is
/// expected to be unavailable.
///
/// `analyze` returns an optional because `ImageAnalysis` has no public
/// initializer: test fakes cannot fabricate one and return `nil` instead. A
/// `nil` result is treated exactly like "no text found" — no button appears.
@MainActor
protocol ImageTextAnalyzing {
    /// Whether this device can analyze images at all. False on the Simulator
    /// and on devices without the required hardware, in which case the viewer
    /// never analyzes and never shows a Live Text button.
    var isSupported: Bool { get }

    /// Analyzes `image` for text and data detectors. Throws on failure and
    /// honours cancellation; both outcomes mean "no Live Text button".
    func analyze(_ image: UIImage) async throws -> ImageAnalysis?
}

/// The production analyzer, backed by VisionKit.
@MainActor
struct SystemImageTextAnalyzer: ImageTextAnalyzing {
    private let analyzer = ImageAnalyzer()

    var isSupported: Bool {
        ImageAnalyzer.isSupported
    }

    func analyze(_ image: UIImage) async throws -> ImageAnalysis? {
        // `.text` covers both text selection and the data detectors built on
        // top of recognized text. `.visualLookUp` and machine-readable codes
        // are deliberately not requested (out of scope).
        try await analyzer.analyze(image, configuration: .init([.text]))
    }
}
```

- [ ] **Step 2: Write the test fake**

Create `SpudTests/FakeImageTextAnalyzer.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit
import VisionKit
@testable import Spud

/// Records analysis requests so tests can assert *when* the viewer decides to
/// analyze. Always resolves to `nil` — `ImageAnalysis` has no public
/// initializer, so the analysis-assignment path is verified on device, not here.
@MainActor
final class FakeImageTextAnalyzer: ImageTextAnalyzing {
    var isSupported: Bool

    /// How many times `analyze` was entered.
    private(set) var analyzeCallCount = 0

    /// How many in-flight analyses were cancelled before completing.
    private(set) var cancelledCallCount = 0

    /// When true, `analyze` suspends until `resumePendingAnalysis()` is called,
    /// so a test can observe an in-flight analysis and cancel it.
    var blocksUntilResumed = false

    private var pendingContinuations: [CheckedContinuation<Void, Error>] = []

    init(isSupported: Bool = true) {
        self.isSupported = isSupported
    }

    func analyze(_: UIImage) async throws -> ImageAnalysis? {
        analyzeCallCount += 1
        guard blocksUntilResumed else { return nil }
        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    pendingContinuations.append(continuation)
                }
            } onCancel: {
                Task { @MainActor in self.failPending(with: CancellationError()) }
            }
        } catch {
            cancelledCallCount += 1
            throw error
        }
        return nil
    }

    /// Lets every suspended `analyze` call return.
    func resumePendingAnalysis() {
        let continuations = pendingContinuations
        pendingContinuations = []
        for continuation in continuations {
            continuation.resume()
        }
    }

    private func failPending(with error: Error) {
        let continuations = pendingContinuations
        pendingContinuations = []
        for continuation in continuations {
            continuation.resume(throwing: error)
        }
    }
}
```

- [ ] **Step 3: Regenerate the project and build**

Run:
```bash
make project && make build
```
Expected: build succeeds. If `SystemImageTextAnalyzer` trips a strict-concurrency diagnostic on `ImageAnalyzer`, keep the `@MainActor` annotation on the struct — do not add `@preconcurrency` or `nonisolated(unsafe)`.

- [ ] **Step 4: Format and commit**

```bash
mint run swiftformat Spud/Scenes/MediaViewer/ImageTextAnalyzing.swift SpudTests/FakeImageTextAnalyzer.swift
git add Spud/Scenes/MediaViewer/ImageTextAnalyzing.swift SpudTests/FakeImageTextAnalyzer.swift
git commit -m "feat: add VisionKit image-text-analysis seam"
```

---

### Task 2: LiveTextController analysis lifecycle

**Files:**
- Create: `Spud/Scenes/MediaViewer/LiveTextController.swift`
- Create: `SpudTests/LiveTextControllerTests.swift`

**Interfaces:**
- Consumes: `ImageTextAnalyzing`, `FakeImageTextAnalyzer` (Task 1).
- Produces: `@MainActor final class LiveTextController` with
  `init(analyzer: any ImageTextAnalyzing = SystemImageTextAnalyzer(), isEnabled: Bool)`,
  `func attach(to imageView: UIImageView)`,
  `func setFinalImage(_ image: UIImage)`,
  `func setPageCurrent(_ isCurrent: Bool)`,
  `func setButtonHidden(_ hidden: Bool, animated: Bool)`,
  `func hasInteractiveItem(at point: CGPoint) -> Bool`,
  `var hasActiveTextSelection: Bool { get }`,
  `var onLiveTextActiveChanged: ((Bool) -> Void)?`,
  and the test seam `func awaitAnalysisForTesting() async`.

- [ ] **Step 1: Write the failing tests**

Create `SpudTests/LiveTextControllerTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
import UIKit
@testable import Spud

/// Verifies when the media viewer decides to run Live Text analysis: only on a
/// supported device, only for a non-animated item, only for the final
/// full-resolution image, and only while its page is the one on screen.
@MainActor
struct LiveTextControllerTests {
    private func image(_ size: CGSize = CGSize(width: 32, height: 32)) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func makeController(
        analyzer: FakeImageTextAnalyzer,
        isEnabled: Bool = true
    ) -> LiveTextController {
        let controller = LiveTextController(analyzer: analyzer, isEnabled: isEnabled)
        controller.attach(to: UIImageView())
        return controller
    }

    @Test
    func doesNotAnalyzeWhenAnalyzerIsUnsupported() async {
        let analyzer = FakeImageTextAnalyzer(isSupported: false)
        let controller = makeController(analyzer: analyzer)

        controller.setPageCurrent(true)
        controller.setFinalImage(image())
        await controller.awaitAnalysisForTesting()

        #expect(analyzer.analyzeCallCount == 0)
    }

    @Test
    func doesNotAnalyzeAnimatedItem() async {
        let analyzer = FakeImageTextAnalyzer()
        let controller = makeController(analyzer: analyzer, isEnabled: false)

        controller.setPageCurrent(true)
        controller.setFinalImage(image())
        await controller.awaitAnalysisForTesting()

        #expect(analyzer.analyzeCallCount == 0)
    }

    @Test
    func doesNotAnalyzeBeforeThePageIsCurrent() async {
        let analyzer = FakeImageTextAnalyzer()
        let controller = makeController(analyzer: analyzer)

        controller.setFinalImage(image())
        await controller.awaitAnalysisForTesting()

        #expect(analyzer.analyzeCallCount == 0)
    }

    @Test
    func analyzesOnceThePageBecomesCurrent() async {
        let analyzer = FakeImageTextAnalyzer()
        let controller = makeController(analyzer: analyzer)

        controller.setFinalImage(image())
        controller.setPageCurrent(true)
        await controller.awaitAnalysisForTesting()

        #expect(analyzer.analyzeCallCount == 1)
    }

    /// The same image arriving twice (a layout pass re-setting it) must not
    /// re-run analysis.
    @Test
    func doesNotReanalyzeTheSameImage() async {
        let analyzer = FakeImageTextAnalyzer()
        let controller = makeController(analyzer: analyzer)
        let sameImage = image()

        controller.setPageCurrent(true)
        controller.setFinalImage(sameImage)
        await controller.awaitAnalysisForTesting()
        controller.setFinalImage(sameImage)
        await controller.awaitAnalysisForTesting()

        #expect(analyzer.analyzeCallCount == 1)
    }

    /// Full resolution replacing an earlier final image re-runs analysis on the
    /// better pixels, cancelling the in-flight pass.
    @Test
    func reanalyzesWhenAHigherResolutionImageArrives() async {
        let analyzer = FakeImageTextAnalyzer()
        analyzer.blocksUntilResumed = true
        let controller = makeController(analyzer: analyzer)

        controller.setPageCurrent(true)
        controller.setFinalImage(image(CGSize(width: 32, height: 32)))
        await Task.yield()
        controller.setFinalImage(image(CGSize(width: 64, height: 64)))
        await Task.yield()

        #expect(analyzer.analyzeCallCount == 2)
        #expect(analyzer.cancelledCallCount == 1)

        analyzer.resumePendingAnalysis()
        await controller.awaitAnalysisForTesting()
    }

    @Test
    func cancelsAnalysisWhenThePageIsNoLongerCurrent() async {
        let analyzer = FakeImageTextAnalyzer()
        analyzer.blocksUntilResumed = true
        let controller = makeController(analyzer: analyzer)

        controller.setPageCurrent(true)
        controller.setFinalImage(image())
        await Task.yield()
        controller.setPageCurrent(false)
        await Task.yield()

        #expect(analyzer.cancelledCallCount == 1)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudTests/LiveTextControllerTests \
  -destination "$(scripts/resolve-test-destination.sh)" \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: compile failure, "cannot find 'LiveTextController' in scope".

- [ ] **Step 3: Write the controller**

Create `Spud/Scenes/MediaViewer/LiveTextController.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit
import VisionKit

/// Drives iOS Live Text for one image view in the media viewer.
///
/// Owns an `ImageAnalysisInteraction` and decides *when* analysis runs. Three
/// conditions must all hold: the device supports analysis, the item is not
/// animated, and the page is the one on screen. Analysis runs on the final
/// full-resolution image only, so a thumbnail is never analyzed and a later
/// full-resolution image cancels and supersedes an in-flight pass.
///
/// Every failure — unsupported device, thrown analysis, cancellation, no text
/// found — resolves to the same visible outcome: no Live Text button.
@MainActor
final class LiveTextController {
    /// Invoked with `true` once an analysis has been applied and the interaction
    /// is live, and with `false` when it is torn down. `ZoomableImageView` uses
    /// this to move its VoiceOver element out of the way of the Live Text button.
    var onLiveTextActiveChanged: ((Bool) -> Void)?

    /// Whether the user currently has text selected in the image. The container
    /// consults this before claiming a swipe-to-dismiss drag.
    var hasActiveTextSelection: Bool {
        interaction.hasActiveTextSelection
    }

    private let analyzer: any ImageTextAnalyzing

    /// False for animated items, which are never analyzed: Live Text on a
    /// moving image is a flat frame that stops matching what is on screen.
    private let isEnabled: Bool

    private let interaction = ImageAnalysisInteraction()

    private weak var imageView: UIImageView?

    /// The most recent final image. Held so analysis can start later, when the
    /// page becomes current.
    private var pendingImage: UIImage?

    /// The image the current analysis was started for, compared by identity so
    /// a repeated `setFinalImage` with the same instance is a no-op.
    private var analyzedImage: UIImage?

    private var isPageCurrent = false
    private var isButtonHidden = true
    private var analysisTask: Task<Void, Never>?

    init(
        analyzer: any ImageTextAnalyzing = SystemImageTextAnalyzer(),
        isEnabled: Bool
    ) {
        self.analyzer = analyzer
        self.isEnabled = isEnabled
        interaction.preferredInteractionTypes = [.textSelection, .dataDetectors]
    }

    deinit {
        analysisTask?.cancel()
    }

    /// Installs the interaction on the image view that displays the photo.
    /// The interaction lives on the zooming image view itself, so text
    /// highlights zoom and pan with the image.
    func attach(to imageView: UIImageView) {
        self.imageView = imageView
        imageView.addInteraction(interaction)
    }

    /// Hands over the final full-resolution image. Safe to call repeatedly;
    /// only a genuinely new image restarts analysis.
    func setFinalImage(_ image: UIImage) {
        guard image !== analyzedImage else { return }
        pendingImage = image
        startAnalysisIfPossible()
    }

    /// Called when this page becomes (or stops being) the one on screen. This
    /// is what makes analysis lazy in a multi-image gallery.
    func setPageCurrent(_ isCurrent: Bool) {
        guard isPageCurrent != isCurrent else { return }
        isPageCurrent = isCurrent
        if isCurrent {
            startAnalysisIfPossible()
        } else {
            cancelAnalysis()
        }
    }

    /// Shows or hides the system Live Text button, so it fades with the rest of
    /// the viewer's chrome.
    func setButtonHidden(_ hidden: Bool, animated: Bool) {
        isButtonHidden = hidden
        interaction.setSupplementaryInterfaceHidden(hidden, animated: animated)
    }

    /// Whether live text, a data detector, or the Live Text button occupies
    /// `point` (in the interaction's image-view coordinate space). The container
    /// uses this to yield its own tap and pan gestures to VisionKit.
    func hasInteractiveItem(at point: CGPoint) -> Bool {
        interaction.hasInteractiveItem(at: point)
    }

    /// Awaits the in-flight analysis so tests can assert deterministically.
    /// Test seam.
    func awaitAnalysisForTesting() async {
        await analysisTask?.value
    }

    /// The button visibility last applied to the interaction. Test seam:
    /// `ImageAnalysisInteraction` exposes no readable equivalent.
    var isButtonHiddenForTesting: Bool {
        isButtonHidden
    }

    // MARK: Private

    private func startAnalysisIfPossible() {
        guard isEnabled, analyzer.isSupported, isPageCurrent, let image = pendingImage else {
            return
        }

        // Supersede any pass still running for an earlier (lower-resolution)
        // image rather than racing it.
        cancelAnalysis()
        analyzedImage = image

        analysisTask = Task { [weak self] in
            guard let self else { return }
            let analysis = try? await analyzer.analyze(image)
            guard !Task.isCancelled else { return }
            apply(analysis)
        }
    }

    private func apply(_ analysis: ImageAnalysis?) {
        interaction.analysis = analysis
        // Adopt whatever chrome state is current, so a button appearing while
        // the chrome is hidden does not pop into view on its own.
        interaction.setSupplementaryInterfaceHidden(isButtonHidden, animated: false)
        onLiveTextActiveChanged?(analysis != nil)
    }

    private func cancelAnalysis() {
        analysisTask?.cancel()
        analysisTask = nil
        analyzedImage = nil
        interaction.analysis = nil
        onLiveTextActiveChanged?(false)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:
```bash
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudTests/LiveTextControllerTests \
  -destination "$(scripts/resolve-test-destination.sh)" \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: `✔ Test run with 7 tests in 1 suite passed`.

If `reanalyzesWhenAHigherResolutionImageArrives` or `cancelsAnalysisWhenThePageIsNoLongerCurrent` is flaky, add one more `await Task.yield()` before the expectation — never a fixed `Task.sleep`, which this codebase has been bitten by under parallel test execution.

- [ ] **Step 5: Format and commit**

```bash
mint run swiftformat Spud/Scenes/MediaViewer/LiveTextController.swift SpudTests/LiveTextControllerTests.swift
git add Spud/Scenes/MediaViewer/LiveTextController.swift SpudTests/LiveTextControllerTests.swift
git commit -m "feat: add Live Text analysis controller for the media viewer"
```

---

### Task 3: Wire Live Text into ZoomableImageView

**Files:**
- Modify: `Spud/Scenes/MediaViewer/ZoomableImageView.swift`
- Create: `SpudTests/ZoomableImageViewLiveTextTests.swift`

**Interfaces:**
- Consumes: `LiveTextController` (Task 2), `FakeImageTextAnalyzer` (Task 1).
- Produces: on `ZoomableImageView` — a new init parameter `liveTextAnalyzer: any ImageTextAnalyzing = SystemImageTextAnalyzer()`, plus
  `func setPageCurrent(_ isCurrent: Bool)`,
  `func setLiveTextButtonHidden(_ hidden: Bool, animated: Bool)`,
  `func hasInteractiveItem(at point: CGPoint) -> Bool` (point in the view's own coordinate space),
  `var hasActiveTextSelection: Bool`,
  and test seams `var isImageAccessibilityElementForTesting: Bool` and `var liveTextDescriptionElementLabelForTesting: String?`.

This task also implements the accessibility swap from the spec: while Live Text is active the image view stops being an accessibility element (so VoiceOver can reach the Live Text button that VisionKit adds as its subview), and the image's own description moves to a dedicated invisible subview inserted at index 0.

- [ ] **Step 1: Write the failing tests**

Create `SpudTests/ZoomableImageViewLiveTextTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit
import Testing
import UIKit
@testable import Spud

/// Verifies the media viewer's zoomable image view drives Live Text correctly:
/// only the final image is analyzed, animated items are skipped, and the
/// VoiceOver element moves aside so the Live Text button stays reachable.
@MainActor
struct ZoomableImageViewLiveTextTests {
    private let screen = CGSize(width: 390, height: 844)

    private func solidImage(
        _ color: UIColor = .systemTeal,
        size: CGSize = CGSize(width: 64, height: 64)
    ) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func makeView(
        item: MediaItem,
        imageService: ImageServiceType,
        analyzer: FakeImageTextAnalyzer
    ) -> ZoomableImageView {
        let view = ZoomableImageView(
            item: item,
            imageService: imageService,
            liveTextAnalyzer: analyzer
        )
        view.frame = CGRect(origin: .zero, size: screen)
        view.layoutIfNeeded()
        return view
    }

    /// A preloaded thumbnail is not the final image and must not be analyzed.
    @Test
    func doesNotAnalyzeAPreloadedThumbnail() async {
        let analyzer = FakeImageTextAnalyzer()
        let view = makeView(
            item: MediaItem(
                imageUrl: URL(filePath: "/full.png"),
                thumbnailUrl: URL(filePath: "/thumb.png"),
                preloadedImage: solidImage()
            ),
            imageService: FakeImageService([.loadingForever]),
            analyzer: analyzer
        )

        view.setPageCurrent(true)
        view.startLoading()
        await view.awaitLoadForTesting()

        #expect(analyzer.analyzeCallCount == 0)
    }

    @Test
    func analyzesTheFinalImageOnTheCurrentPage() async {
        let analyzer = FakeImageTextAnalyzer()
        let view = makeView(
            item: MediaItem(imageUrl: URL(filePath: "/full.png")),
            imageService: FakeImageService([.ready(solidImage())]),
            analyzer: analyzer
        )

        view.setPageCurrent(true)
        view.startLoading()
        await view.awaitLoadForTesting()
        await view.awaitLiveTextAnalysisForTesting()

        #expect(analyzer.analyzeCallCount == 1)
    }

    @Test
    func doesNotAnalyzeAnAnimatedItem() async {
        let analyzer = FakeImageTextAnalyzer()
        let view = makeView(
            item: MediaItem(imageUrl: URL(filePath: "/animation.gif")),
            imageService: FakeImageService([.ready(solidImage())]),
            analyzer: analyzer
        )

        view.setPageCurrent(true)
        view.startLoading()
        await view.awaitLoadForTesting()
        await view.awaitLiveTextAnalysisForTesting()

        #expect(analyzer.analyzeCallCount == 0)
    }

    /// Before Live Text is active the image view carries the VoiceOver element
    /// itself, exactly as it did before this feature.
    @Test
    func imageViewIsTheAccessibilityElementByDefault() {
        let view = makeView(
            item: MediaItem(imageUrl: URL(filePath: "/full.png")),
            imageService: FakeImageService([.loadingForever]),
            analyzer: FakeImageTextAnalyzer()
        )

        #expect(view.isImageAccessibilityElementForTesting)
        #expect(view.liveTextDescriptionElementLabelForTesting == nil)
    }

    /// Once Live Text is active the image view must stop being an accessibility
    /// element, or it would hide the Live Text button VisionKit adds as its
    /// subview from VoiceOver. The image's own description moves to a dedicated
    /// element so it is not lost.
    @Test
    func liveTextMovesTheAccessibilityElementAside() {
        let view = makeView(
            item: MediaItem(imageUrl: URL(filePath: "/full.png")),
            imageService: FakeImageService([.loadingForever]),
            analyzer: FakeImageTextAnalyzer()
        )

        view.setLiveTextActive(true)

        #expect(!view.isImageAccessibilityElementForTesting)
        #expect(view.liveTextDescriptionElementLabelForTesting == "Image")
    }

    @Test
    func accessibilityElementIsRestoredWhenLiveTextGoesAway() {
        let view = makeView(
            item: MediaItem(imageUrl: URL(filePath: "/full.png")),
            imageService: FakeImageService([.loadingForever]),
            analyzer: FakeImageTextAnalyzer()
        )

        view.setLiveTextActive(true)
        view.setLiveTextActive(false)

        #expect(view.isImageAccessibilityElementForTesting)
        #expect(view.liveTextDescriptionElementLabelForTesting == nil)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudTests/ZoomableImageViewLiveTextTests \
  -destination "$(scripts/resolve-test-destination.sh)" \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: compile failure — `ZoomableImageView` has no `liveTextAnalyzer:` parameter.

- [ ] **Step 3: Add the Live Text controller to ZoomableImageView**

In `Spud/Scenes/MediaViewer/ZoomableImageView.swift`:

Add after the `onFullImageUnavailable` property:

```swift
    // MARK: Live Text

    /// Whether the user currently has text selected in the image. The container
    /// consults this before claiming a swipe-to-dismiss drag.
    var hasActiveTextSelection: Bool {
        liveTextController.hasActiveTextSelection
    }

    /// Called when this page becomes (or stops being) the one on screen, which
    /// is what gates Live Text analysis to the visible page.
    func setPageCurrent(_ isCurrent: Bool) {
        liveTextController.setPageCurrent(isCurrent)
    }

    /// Fades the system Live Text button in and out with the viewer's chrome.
    func setLiveTextButtonHidden(_ hidden: Bool, animated: Bool) {
        liveTextController.setButtonHidden(hidden, animated: animated)
    }

    /// Whether live text, a data detector, or the Live Text button occupies
    /// `point`, given in this view's coordinate space.
    func hasInteractiveItem(at point: CGPoint) -> Bool {
        liveTextController.hasInteractiveItem(at: convert(point, to: imageView))
    }
```

Add to the test seams section:

```swift
    /// Whether the image view is still the VoiceOver element. Test seam.
    var isImageAccessibilityElementForTesting: Bool {
        imageView.isAccessibilityElement
    }

    /// The label of the stand-in VoiceOver element used while Live Text is
    /// active, or nil when it isn't installed. Test seam.
    var liveTextDescriptionElementLabelForTesting: String? {
        imageDescriptionView?.accessibilityLabel
    }

    /// Awaits the in-flight Live Text analysis. Test seam.
    func awaitLiveTextAnalysisForTesting() async {
        await liveTextController.awaitAnalysisForTesting()
    }

    /// Whether the Live Text button is currently hidden. Test seam.
    var isLiveTextButtonHiddenForTesting: Bool {
        liveTextController.isButtonHiddenForTesting
    }
```

Add to the private properties:

```swift
    private let liveTextController: LiveTextController

    /// An invisible stand-in that carries the image's VoiceOver description
    /// while Live Text is active. See `setLiveTextActive(_:)`.
    private var imageDescriptionView: UIView?
```

Change the initializer signature and body:

```swift
    init(
        item: MediaItem,
        imageService: ImageServiceType,
        gracePeriod: Duration = .milliseconds(400),
        liveTextAnalyzer: any ImageTextAnalyzing = SystemImageTextAnalyzer()
    ) {
        self.item = item
        self.imageService = imageService
        self.gracePeriod = gracePeriod
        // Animated items are never analyzed: Live Text on a moving image is a
        // flat frame that stops matching what is on screen.
        liveTextController = LiveTextController(
            analyzer: liveTextAnalyzer,
            isEnabled: !item.isAnimated
        )
        super.init(frame: .zero)
```

Immediately after `scrollView.addSubview(imageView)` in the initializer, add:

```swift
        liveTextController.attach(to: imageView)
        liveTextController.onLiveTextActiveChanged = { [weak self] isActive in
            self?.setLiveTextActive(isActive)
        }
```

In `setImage(_:isFinal:)`, add right after `imageView.image = image`:

```swift
        if isFinal {
            liveTextController.setFinalImage(image)
        }
```

Add this method after `setImage(_:isFinal:)`. It is deliberately **internal, not private** — the accessibility tests call it directly, because a fake analyzer cannot produce a real analysis to trigger it:

```swift
    /// Moves the VoiceOver element aside while Live Text is active.
    ///
    /// `ImageAnalysisInteraction` adds its Live Text button as a subview of the
    /// image view, and an accessibility element hides its own descendants from
    /// VoiceOver — so leaving `imageView.isAccessibilityElement` true would make
    /// the button unreachable. Instead the image view stops being an element and
    /// an invisible stand-in, inserted below the button, carries the image's
    /// description so it is not lost.
    func setLiveTextActive(_ isActive: Bool) {
        guard isActive != (imageDescriptionView != nil) else { return }

        if isActive {
            let descriptionView = UIView()
            descriptionView.isUserInteractionEnabled = false
            descriptionView.backgroundColor = .clear
            descriptionView.frame = imageView.bounds
            descriptionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            descriptionView.isAccessibilityElement = true
            descriptionView.accessibilityTraits = .image
            descriptionView.accessibilityLabel = imageView.accessibilityLabel
            imageView.insertSubview(descriptionView, at: 0)
            imageDescriptionView = descriptionView
            imageView.isAccessibilityElement = false
        } else {
            imageDescriptionView?.removeFromSuperview()
            imageDescriptionView = nil
            imageView.isAccessibilityElement = true
        }
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:
```bash
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudTests/ZoomableImageViewLiveTextTests \
  -destination "$(scripts/resolve-test-destination.sh)" \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: `✔ Test run with 6 tests in 1 suite passed`.

- [ ] **Step 5: Run the existing media-viewer tests for regressions**

Run:
```bash
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudTests/ZoomableImageViewLoadingIndicatorTests \
  -only-testing:SpudTests/MediaViewerGlassButtonsHitTestTests \
  -destination "$(scripts/resolve-test-destination.sh)" \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: all pass. The new init parameter is defaulted, so no existing call site changes.

- [ ] **Step 6: Format and commit**

```bash
mint run swiftformat Spud/Scenes/MediaViewer/ZoomableImageView.swift SpudTests/ZoomableImageViewLiveTextTests.swift
git add Spud/Scenes/MediaViewer/ZoomableImageView.swift SpudTests/ZoomableImageViewLiveTextTests.swift
git commit -m "feat: drive Live Text analysis from the zoomable image view"
```

---

### Task 4: Per-page gating and chrome mirroring

**Files:**
- Modify: `Spud/Scenes/MediaViewer/MediaViewerPageViewController.swift`
- Modify: `Spud/Scenes/MediaViewer/MediaViewerViewController.swift` (`viewDidLoad` around line 391, `setBar(hidden:animated:)` around line 619, `didFinishAnimating` around line 942)
- Create: `SpudTests/MediaViewerLiveTextChromeTests.swift`

**Interfaces:**
- Consumes: `ZoomableImageView.setPageCurrent(_:)`, `setLiveTextButtonHidden(_:animated:)`, `isLiveTextButtonHiddenForTesting` (Task 3).
- Produces: `MediaViewerPageViewController.isCurrentPage: Bool`; `MediaViewerViewController.toggleChromeForTesting()`.

- [ ] **Step 1: Write the failing test**

Create `SpudTests/MediaViewerLiveTextChromeTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit
import Testing
import UIKit
@testable import Spud

/// Verifies the Live Text button behaves as chrome: hidden when the viewer
/// opens clean, revealed with the top bar, hidden again with it.
@MainActor
struct MediaViewerLiveTextChromeTests {
    private func solidImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }
    }

    private func makeViewController() -> MediaViewerViewController {
        let viewController = MediaViewerViewController(
            items: [MediaItem(imageUrl: URL(filePath: "/full.png"))],
            initialIndex: 0,
            imageService: FakeImageService([.ready(solidImage())])
        )
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.view.layoutIfNeeded()
        return viewController
    }

    /// The viewer opens with the chrome hidden, so the Live Text button starts
    /// hidden too — the photo is undecorated.
    @Test
    func buttonStartsHiddenWithTheChrome() {
        let viewController = makeViewController()

        #expect(viewController.isLiveTextButtonHiddenForTesting == true)
    }

    @Test
    func buttonFollowsTheChromeWhenToggled() {
        let viewController = makeViewController()

        viewController.toggleChromeForTesting()
        #expect(viewController.isLiveTextButtonHiddenForTesting == false)

        viewController.toggleChromeForTesting()
        #expect(viewController.isLiveTextButtonHiddenForTesting == true)
    }

    /// The first page must be marked current, or it would never analyze.
    @Test
    func firstPageIsMarkedCurrent() {
        let viewController = makeViewController()

        #expect(viewController.currentPageIsCurrentForTesting == true)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudTests/MediaViewerLiveTextChromeTests \
  -destination "$(scripts/resolve-test-destination.sh)" \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: compile failure — `toggleChromeForTesting` does not exist.

If `MediaViewerViewController`'s initializer signature differs from the one used above, copy the exact signature from `SpudTests/MediaViewerShareTests.swift`, which already constructs one.

- [ ] **Step 3: Add `isCurrentPage` to the page view controller**

In `Spud/Scenes/MediaViewer/MediaViewerPageViewController.swift`, add after `isShowingLowResPreviewOnly`:

```swift
    /// Whether this page is the one on screen. Live Text analysis is gated on
    /// this so a multi-image gallery analyzes lazily, page by page, rather than
    /// analyzing every image the page view controller preloads.
    var isCurrentPage = false {
        didSet {
            guard isCurrentPage != oldValue else { return }
            zoomableImageView.setPageCurrent(isCurrentPage)
        }
    }
```

- [ ] **Step 4: Mark the first page current**

In `MediaViewerViewController.viewDidLoad`, immediately after the existing `pageViewController.setViewControllers([firstPage], direction: .forward, animated: false)` line, add:

```swift
        firstPage.isCurrentPage = true
```

- [ ] **Step 5: Track the current page across paging**

In `MediaViewerViewController`'s `pageViewController(_:didFinishAnimating:previousViewControllers:transitionCompleted:)`, replace the body with:

```swift
        guard completed, let page = currentPage else { return }
        for previous in previousViewControllers.compactMap({ $0 as? MediaViewerPageViewController })
            where previous !== page
        {
            previous.isCurrentPage = false
        }
        page.isCurrentPage = true
        currentIndex = page.pageIndex
        pageControl.currentPage = currentIndex
        updateCaption()
        updateLowResPreviewPill()
        updateLiveTextButtonVisibility(animated: false)
```

- [ ] **Step 6: Mirror chrome visibility onto the Live Text button, and add the test seams**

In `MediaViewerViewController`, add to the end of `setBar(hidden:animated:)`, after the existing `UIView.animate(...)` call:

```swift
        // The Live Text button is chrome: it fades with the top bar so the
        // viewer still offers a clean, undecorated photo.
        updateLiveTextButtonVisibility(animated: animated)
```

Note the method has an early `return` in its `guard animated, ...` branch. Restructure so the new call runs on both paths:

```swift
    private func setBar(hidden: Bool, animated: Bool = true) {
        isBarHidden = hidden
        let alpha: CGFloat = hidden ? 0 : 1
        let changes = { [self] in
            topBarBackgroundView.alpha = alpha
            pageControl.alpha = alpha
            captionContainer.alpha = alpha
            lowResPreviewPill.alpha = alpha
        }
        if animated, !UIAccessibility.isReduceMotionEnabled {
            UIView.animate(
                withDuration: 0.3,
                delay: 0,
                usingSpringWithDamping: 0.9,
                initialSpringVelocity: 0,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: changes
            )
        } else {
            changes()
        }
        // The Live Text button is chrome: it fades with the top bar so the
        // viewer still offers a clean, undecorated photo.
        updateLiveTextButtonVisibility(animated: animated)
    }

    /// Applies the current chrome visibility to the on-screen page's Live Text
    /// button. Also called on a page change, so a newly revealed page adopts the
    /// chrome state instead of showing a stray button.
    private func updateLiveTextButtonVisibility(animated: Bool) {
        currentPage?.zoomableImageView.setLiveTextButtonHidden(
            isBarHidden,
            animated: animated && !UIAccessibility.isReduceMotionEnabled
        )
    }
```

Then add the two test seams the Step 1 tests need, near the other private properties:

```swift
    /// Toggles the chrome exactly as a single tap does. Test seam.
    func toggleChromeForTesting() {
        setBar(hidden: !isBarHidden, animated: false)
    }

    /// Whether the on-screen page's Live Text button is hidden. Test seam.
    var isLiveTextButtonHiddenForTesting: Bool? {
        currentPage?.zoomableImageView.isLiveTextButtonHiddenForTesting
    }

    /// Whether the on-screen page has been marked current, which is what gates
    /// its Live Text analysis. Test seam.
    var currentPageIsCurrentForTesting: Bool? {
        currentPage?.isCurrentPage
    }
```

- [ ] **Step 7: Build and run the media-viewer test suites**

Run:
```bash
mint run swiftformat Spud/Scenes/MediaViewer/ SpudTests/
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudTests/MediaViewerLiveTextChromeTests \
  -only-testing:SpudTests/ZoomableImageViewLiveTextTests \
  -only-testing:SpudTests/ZoomableImageViewLoadingIndicatorTests \
  -only-testing:SpudTests/MediaViewerGlassButtonsHitTestTests \
  -only-testing:SpudTests/MediaViewerShareTests \
  -destination "$(scripts/resolve-test-destination.sh)" \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: all pass.

- [ ] **Step 8: Commit**

```bash
git add Spud/Scenes/MediaViewer/MediaViewerPageViewController.swift Spud/Scenes/MediaViewer/MediaViewerViewController.swift SpudTests/MediaViewerLiveTextChromeTests.swift
git commit -m "feat: gate Live Text to the visible page and fade its button with the chrome"
```

---

### Task 5: Gesture arbitration

**Files:**
- Modify: `Spud/Scenes/MediaViewer/MediaViewerViewController.swift` (the `UIGestureRecognizerDelegate` extension, around lines 958-984)
- Create: `SpudTests/MediaViewerLiveTextGestureTests.swift`

**Interfaces:**
- Consumes: `ZoomableImageView.hasInteractiveItem(at:)` and `hasActiveTextSelection` (Task 3).
- Produces: nothing new; changes the behavior of the two existing delegate methods.

The delegate methods are private-by-extension but the type is `@testable import`-visible; tests call them directly through the `UIGestureRecognizerDelegate` conformance.

- [ ] **Step 1: Write the failing tests**

Create `SpudTests/MediaViewerLiveTextGestureTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit
import Testing
import UIKit
@testable import Spud

/// Verifies the media viewer yields its own gestures to Live Text: the
/// chrome-toggling tap and the swipe-to-dismiss drag must not fire on top of
/// selectable text, a data detector, or the Live Text button.
@MainActor
struct MediaViewerLiveTextGestureTests {
    private func solidImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }
    }

    private func makeViewController() -> MediaViewerViewController {
        let viewController = MediaViewerViewController(
            items: [MediaItem(imageUrl: URL(filePath: "/full.png"))],
            initialIndex: 0,
            imageService: FakeImageService([.ready(solidImage())])
        )
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.view.layoutIfNeeded()
        return viewController
    }

    /// The dismiss pan is a downward, mostly-vertical drag on an un-zoomed
    /// image. Without live text under the touch it is still claimed.
    @Test
    func dismissPanIsClaimedWithoutLiveTextUnderTheTouch() {
        let viewController = makeViewController()
        let pan = StubPanGestureRecognizer(velocity: CGPoint(x: 0, y: 800))

        #expect(viewController.gestureRecognizerShouldBegin(pan))
    }

    /// An upward drag is never the dismiss gesture, live text or not.
    @Test
    func upwardPanIsNotClaimed() {
        let viewController = makeViewController()
        let pan = StubPanGestureRecognizer(velocity: CGPoint(x: 0, y: -800))

        #expect(!viewController.gestureRecognizerShouldBegin(pan))
    }

    /// With text selected, a downward drag belongs to the selection, not to
    /// swipe-to-dismiss.
    @Test
    func dismissPanIsRefusedWhileTextIsSelected() {
        let viewController = makeViewController()
        viewController.liveTextSelectionActiveOverrideForTesting = true
        let pan = StubPanGestureRecognizer(velocity: CGPoint(x: 0, y: 800))

        #expect(!viewController.gestureRecognizerShouldBegin(pan))
    }

    /// A drag starting on live text or on the Live Text button belongs to
    /// VisionKit.
    @Test
    func dismissPanIsRefusedOnAnInteractiveItem() {
        let viewController = makeViewController()
        viewController.liveTextInteractiveItemOverrideForTesting = true
        let pan = StubPanGestureRecognizer(velocity: CGPoint(x: 0, y: 800))

        #expect(!viewController.gestureRecognizerShouldBegin(pan))
    }
}

/// A pan recognizer with a canned velocity, so a gesture-arbitration test does
/// not need a real touch sequence.
private final class StubPanGestureRecognizer: UIPanGestureRecognizer {
    private let stubbedVelocity: CGPoint

    init(velocity: CGPoint) {
        stubbedVelocity = velocity
        super.init(target: nil, action: nil)
    }

    override func velocity(in _: UIView?) -> CGPoint {
        stubbedVelocity
    }

    override func location(in _: UIView?) -> CGPoint {
        CGPoint(x: 100, y: 100)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudTests/MediaViewerLiveTextGestureTests \
  -destination "$(scripts/resolve-test-destination.sh)" \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: compile failure — `liveTextSelectionActiveOverrideForTesting` does not exist.

If `MediaViewerViewController`'s initializer signature differs from the one used in `makeViewController()`, copy the exact signature from `SpudTests/MediaViewerShareTests.swift`, which already constructs one.

- [ ] **Step 3: Add the test overrides and the arbitration**

In `MediaViewerViewController`, add alongside the test seams added in Task 4:

```swift
    /// Forces `hasActiveTextSelection` for gesture-arbitration tests, which
    /// cannot produce a real Live Text selection in the Simulator. Test seam.
    var liveTextSelectionActiveOverrideForTesting: Bool?

    /// Forces `hasInteractiveItem(at:)` for gesture-arbitration tests. Test seam.
    var liveTextInteractiveItemOverrideForTesting: Bool?

    private var hasActiveLiveTextSelection: Bool {
        liveTextSelectionActiveOverrideForTesting
            ?? (currentPage?.zoomableImageView.hasActiveTextSelection ?? false)
    }

    private func hasLiveTextInteractiveItem(at pointInView: CGPoint) -> Bool {
        if let override = liveTextInteractiveItemOverrideForTesting {
            return override
        }
        guard let zoomable = currentPage?.zoomableImageView else { return false }
        return zoomable.hasInteractiveItem(at: view.convert(pointInView, to: zoomable))
    }
```

Then replace the two delegate methods in the `UIGestureRecognizerDelegate` extension:

```swift
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        guard gestureRecognizer === singleTapGesture else { return true }

        // A tap on the alt-text pill opens its sheet; don't also toggle the
        // chrome out from under it.
        if let touchView = touch.view, touchView.isDescendant(of: captionContainer) {
            return false
        }

        // A tap on live text, a data detector, or the Live Text button belongs
        // to VisionKit; toggling the chrome would steal it.
        if hasLiveTextInteractiveItem(at: touch.location(in: view)) {
            return false
        }

        return true
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        // Only claim a downward, mostly-vertical drag, and only when the
        // current image isn't zoomed (so panning a zoomed image still works).
        if currentPage?.zoomableImageView.isZoomed == true {
            return false
        }
        // Dragging to extend a text selection, or dragging from live text or the
        // Live Text button, is VisionKit's gesture, not swipe-to-dismiss.
        if hasActiveLiveTextSelection || hasLiveTextInteractiveItem(at: pan.location(in: view)) {
            return false
        }
        let velocity = pan.velocity(in: view)
        return velocity.y > 0 && abs(velocity.y) > abs(velocity.x)
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:
```bash
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudTests/MediaViewerLiveTextGestureTests \
  -destination "$(scripts/resolve-test-destination.sh)" \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: `✔ Test run with 4 tests in 1 suite passed`.

- [ ] **Step 5: Run the full SpudTests target**

Run:
```bash
mint run swiftformat Spud/ SpudTests/
make test-only ONLY=SpudTests
```
Expected: the whole target passes. This target runs in parallel — a failure that passes in isolation is usually a wall-clock timeout, not a regression; re-read the CLAUDE.md note on `waitUntil` before "fixing" one.

- [ ] **Step 6: Commit**

```bash
git add Spud/Scenes/MediaViewer/MediaViewerViewController.swift SpudTests/MediaViewerLiveTextGestureTests.swift
git commit -m "feat: yield media-viewer tap and dismiss gestures to Live Text"
```

---

### Task 6: Documentation and on-device verification

**Files:**
- Modify: `docs/features/media-viewer.md`
- Modify: `docs/features/README.md`

**Interfaces:**
- Consumes: the shipped behavior from Tasks 1-5.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Document the behavior**

In `docs/features/media-viewer.md`, add to the "Behavior and rules" list, after the "Alt text" bullet:

```markdown
- **Live Text.** When an image contains text, iOS's Live Text button appears over the
  photo and the text becomes selectable — with the system's Copy / Look Up / Translate /
  Share menu — and phone numbers, addresses, and URLs baked into the image are tappable.
  The button is part of the chrome: it fades in and out with the top bar and page dots,
  so the viewer still opens as a clean, undecorated photo. Only the full-resolution image
  is analyzed (never a thumbnail or a low-resolution preview), only the image currently on
  screen in a gallery, and never an animated GIF. Analysis runs entirely on the device.
  While text is selected, or while a touch is on live text or on the button itself, the
  viewer yields its own gestures: the tap doesn't toggle the chrome and a downward drag
  doesn't dismiss. Pinch, double-tap zoom, and paging are unaffected. Devices that don't
  support image analysis simply never show the button.
```

Add to the "Scenarios" section, after the alt-text scenarios:

```markdown
### Select text in an image

- **Given** an image containing text, open in the viewer
- **When** I tap to show the chrome and tap the Live Text button
- **Then** the text in the image becomes selectable, with Copy, Look Up, Translate, and Share
- **And** tapping to hide the chrome hides the Live Text button along with the top bar

### A tappable link inside an image

- **Given** an image containing a URL, phone number, or address
- **When** Live Text is active and I tap it
- **Then** iOS offers to open it
- **And** the tap neither toggles the chrome nor dismisses the viewer

### Live Text is skipped where it doesn't apply

- **Given** an animated GIF, or an image whose full resolution failed to load and is showing
  only a low-resolution preview
- **When** I open it in the viewer
- **Then** no Live Text button appears
```

Add to "Not supported / out of scope":

```markdown
- Live Text covers text and data detectors only — subject lift ("lift the subject from the
  background") and Visual Look Up are not offered.
- Live Text is offered in the full-screen viewer only, not on feed thumbnails, post-detail
  header images, or inline body images.
- A URL tapped inside an image is handed to iOS directly; it does not go through Spud's URL
  sanitizer or the in-app-browser preference, because VisionKit provides no hook for it.
```

- [ ] **Step 2: Update both README index sections**

In `docs/features/README.md`, the media-viewer row in the capability table and its entry in the "Feature coverage by area" map both need Live Text reflected in their summaries. Read the existing wording for the media viewer in both sections and extend it — they drift independently, so update both.

- [ ] **Step 3: Verify the docs index**

Confirm `media-viewer.md` is listed in **both** README sections and that neither summary is now stale:

```bash
grep -n "media-viewer" docs/features/README.md
```
Expected: at least two hits — one in the capability table, one in the "Feature coverage by area" map. The `ddenis:feature-docs` skill carries an `audit_feature_docs.py` that checks this mechanically; invoke the skill if you want the full audit.

- [ ] **Step 4: Commit the docs**

```bash
git add docs/features/media-viewer.md docs/features/README.md
git commit -m "docs: document Live Text in the media viewer"
```

- [ ] **Step 5: On-device verification — REQUIRED, cannot be skipped**

Build and run on a **physical device** (Live Text is expected to be unavailable in the Simulator, so every preceding green test proves only that the plumbing is right).

Walk through and confirm each:

1. Open a post image containing text. Tap to show the chrome — the Live Text button appears bottom-trailing over the photo.
2. Tap the Live Text button. Text highlights and is selectable; the selection menu offers Copy, Look Up, Translate, Share.
3. Tap to hide the chrome. The Live Text button fades away with the top bar.
4. Drag down starting on live text — the viewer does **not** dismiss. Drag down starting on blank image area — it does.
5. Pinch and double-tap zoom still work; text highlights zoom with the image.
6. In a multi-image post, page to a second image containing text — its button appears; page back — no stray button on the wrong page.
7. Open an animated GIF — no Live Text button.
8. Open an image with a URL in it and tap the URL — iOS offers to open it.
9. **VoiceOver on:** swipe through the viewer with Live Text active. Confirm the image's description is still announced **and** the Live Text button is reachable. This is the accessibility risk flagged in the spec — if the button is unreachable, fall back to leaving the image view as the accessibility element and exposing the recognized text as a custom accessibility action instead.

- [ ] **Step 6: Report honestly**

Record which of the nine checks passed and which did not. Do not describe the feature as done while any check is unverified — say plainly which ones were not exercised and why.

---

## Notes for the implementer

- **Do not add `#available(iOS 26, *)` guards.** The floor is 26.0.
- **Do not add snapshot tests.** The Live Text button is system-drawn and will not render in the Simulator; a recorded reference would be a picture of nothing.
- **Do not widen `preferredInteractionTypes`.** Subject lift and Visual Look Up were considered and explicitly rejected.
- **Do not "fix" the fake analyzer to return a real `ImageAnalysis`.** It has no public initializer; this limitation is designed around, not overcome.
- This is a shared checkout that parallel agents also use. Verify `git branch --show-current` before committing, stage explicit paths (never `git add -A`), and never edit anything under `.claude/worktrees/`.
