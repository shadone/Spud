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
