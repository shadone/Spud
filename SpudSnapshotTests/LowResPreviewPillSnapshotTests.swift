//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SnapshotTesting
import UIKit
import XCTest
@testable import Spud

/// Visual coverage for ``LowResPreviewPillView`` in both of its shipped
/// configurations — the post-detail header's interactive "tap to retry" pill
/// and the media viewer's informational one.
///
/// The pill had no snapshot coverage of its own until now. It was captured only
/// incidentally, inside `PostDetailHeaderSnapshotTests.test_image_lowResPreview`
/// — and that reference was once recorded while the pill was rendering
/// illegibly (light-tinted glass with white text on it, the `UIGlassEffect`
/// trait-tint defect), shipped as ground truth, and caught only later by a byte
/// size mismatch during a merge. A snapshot cannot tell "correct" from
/// "stable", so these references are the *shape* record only; legibility itself
/// is asserted numerically in `SpudTests/LowResPreviewPillContrastTests`.
///
/// Two things make these references meaningful:
///
/// - **On-screen capture** (`drawHierarchyInKeyWindow: true`). The default
///   offscreen `layer.render(in:)` strategy does not composite
///   `UIVisualEffectView` material at all, so an offscreen reference of a glass
///   pill records the material as *absent* — indistinguishable from a broken
///   one, and unable to ever regress. See `SpudSnapshotTests/CLAUDE.md`.
/// - **Both host traits, deliberately expected to match.** The pill pins
///   `overrideUserInterfaceStyle = .dark` because its content is fixed white
///   and `UIGlassEffect` tints from the inherited trait. So the light and dark
///   references of the same backdrop should look the same; if a future change
///   drops the pin, the light one turns near-white and diverges. That is the
///   regression this class exists to catch, and it mirrors
///   `MediaViewerChromeSnapshotTests`' approach to the identical defect.
///
/// Backdrops are flat fills standing in for a photo: the material samples what
/// is behind it, so a bright fill and a near-black one bracket the real range
/// (and the near-black one is where the pill's silhouette measurably fades into
/// the backdrop while its text gets *more* legible — see the contrast suite).
@MainActor
final class LowResPreviewPillSnapshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // On-screen captures inherit the host app's launch tint and the sim's
        // persisted orientation/status-bar state; pin both.
        SnapshotDeterminism.pinAccent()
        SnapshotDeterminism.pinStatusBarHidden()
    }

    /// The post-detail header's pill: title plus the retry chevron, over a
    /// bright photo — the backdrop where the glass tints lightest and fixed
    /// white content is hardest to keep legible.
    func test_pill_retry_overBrightBackdrop() {
        assertBothAppearances(interactive: true, backdrop: UIColor(white: 0.95, alpha: 1))
    }

    /// The media viewer's informational pill (no retry chevron), over a
    /// near-black photo — the media viewer's normal case.
    func test_pill_informational_overDarkBackdrop() {
        assertBothAppearances(interactive: false, backdrop: UIColor(white: 0.08, alpha: 1))
    }

    // MARK: - Helpers

    private func assertBothAppearances(
        interactive: Bool,
        backdrop: UIColor,
        testName: String = #function,
        line: UInt = #line
    ) {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let host = makeHost(interactive: interactive, backdrop: backdrop)
            assertSnapshot(
                matching: host,
                as: .image(
                    drawHierarchyInKeyWindow: true,
                    size: host.bounds.size,
                    traits: traits(style)
                ),
                named: style == .dark ? "dark" : "light",
                testName: testName,
                line: line
            )
        }
    }

    private func makeHost(interactive: Bool, backdrop: UIColor) -> UIView {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 280, height: 92))
        host.backgroundColor = backdrop

        let pill = LowResPreviewPillView(
            title: interactive ? "Low-res preview · tap to retry" : "Showing low-resolution preview",
            showsRetryHint: interactive
        )
        host.addSubview(pill)
        NSLayoutConstraint.activate([
            pill.centerXAnchor.constraint(equalTo: host.centerXAnchor),
            pill.centerYAnchor.constraint(equalTo: host.centerYAnchor),
        ])
        host.layoutIfNeeded()
        return host
    }

    private func traits(_ style: UIUserInterfaceStyle) -> UITraitCollection {
        UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: style),
            UITraitCollection(displayScale: 2),
            SnapshotDeterminism.contentSizeTrait,
        ])
    }
}
