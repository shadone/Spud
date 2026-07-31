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

    /// - Parameters:
    ///   - analyzer: The seam over VisionKit; defaults to the real
    ///     `SystemImageTextAnalyzer`, so production call sites only need to pass
    ///     `isEnabled`. Tests inject a fake.
    ///   - isEnabled: Whether this item is eligible for analysis at all — pass
    ///     `false` for an animated item (GIF/video), which is never analyzed.
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
