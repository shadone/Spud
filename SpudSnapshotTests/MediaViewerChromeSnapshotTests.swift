//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SnapshotTesting
import SpudDataKit
import UIKit
import XCTest
@testable import Spud

/// Covers the media viewer's floating chrome — close/share/save (`.glass()`
/// buttons inside `topBarBackgroundView`) and the caption pill
/// (`captionContainer`) — in its VISIBLE state.
///
/// Before this class, the only snapshot coverage of `MediaViewerViewController`
/// was `MediaViewerCenteringSnapshotTests.test_mediaViewer_chromeHiddenByDefault`,
/// which captures the chrome at `alpha == 0` (hidden) — so the converted
/// `.glass()` buttons and the `GlassTokens.controlSurface` bars were never
/// actually rendered by an automated test. That gap is exactly what let Task
/// 17's accessibility pass find (and fix) a real defect: `GlassTokens.controlSurface`
/// (`UIGlassEffect(.regular)`) bases its tint on the CURRENT trait environment,
/// not just backdrop luminosity, so the chrome rendered light-toned — with its
/// fixed-`.white` text/icons nearly illegible — whenever the app's Appearance
/// preference was Light (`MediaViewerViewController` now forces
/// `overrideUserInterfaceStyle = .dark` to match its always-dark visual design;
/// see that file's `viewDidLoad`). These two tests are the regression guard for
/// that fix: they force an EXTERNAL host trait via `traits:` before capture, so
/// a future change that reintroduces trait-dependent rendering would fail here
/// even though the surrounding host app trait varies.
///
/// Uses the on-screen `drawHierarchyInKeyWindow: true` capture strategy: like
/// any `UIVisualEffectView`/`UIGlassEffect` surface, this chrome renders
/// invisible under the default offscreen `.image(size:traits:)` path (see
/// `SpudSnapshotTests/CLAUDE.md`).
@MainActor
final class MediaViewerChromeSnapshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        SnapshotDeterminism.pinStatusBarHidden()
    }

    private struct Deps: HasImageService {
        let imageService: ImageServiceType
    }

    private let screen = CGSize(width: 390, height: 844)

    private func traits(_ style: UIUserInterfaceStyle) -> UITraitCollection {
        UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: style),
            UITraitCollection(displayScale: 2),
            SnapshotDeterminism.contentSizeTrait,
        ])
    }

    private func photo(_ color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: screen).image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: screen))
        }
    }

    /// Reveals the auto-hiding chrome (normally hidden until a single tap) and
    /// the caption pill (normally hidden when the item carries no alt text),
    /// mirroring `MediaViewerGlassButtonsHitTestTests`'s approach.
    private func revealChrome(_ view: UIView) {
        // Deliberately reveals only the chrome subtree, not every descendant of
        // `vc.view`. An earlier blanket recursion also un-hid
        // `ZoomableImageView`'s normally-hidden failure glyph, so the recorded
        // references showed a broken-image icon over what is documented as a
        // clean bright photo — and coupled this chrome test to an unrelated
        // internal detail of another view's error UI.
        //
        // Scope note: `LowResPreviewPillView` is NOT revealed here (it is
        // wrapped in a plain `UIView`, not a direct effect-view child). It
        // carries the same fixed-white-on-adaptive-glass risk this class
        // guards against and has no snapshot coverage of its own — worth a
        // dedicated test rather than widening this one, which exists to cover
        // the top bar and caption pill.
        for chrome in view.subviews where chrome is UIVisualEffectView || chrome is UIPageControl {
            reveal(chrome)
        }
    }

    /// Un-hides a chrome view and everything inside it.
    private func reveal(_ view: UIView) {
        view.alpha = 1
        view.isHidden = false
        for subview in view.subviews {
            reveal(subview)
        }
    }

    /// The top bar (close/share/save) and caption pill, visible, over a bright
    /// backdrop — the higher-risk case for the fixed-white-on-adaptive-glass
    /// defect this class guards against. Captured under both a light and a
    /// dark HOST trait to prove `overrideUserInterfaceStyle = .dark` makes the
    /// chrome's own rendering independent of the app's Appearance preference.
    func test_chromeVisible_overBrightPhoto_light() {
        assertChromeVisible(style: .light)
    }

    func test_chromeVisible_overBrightPhoto_dark() {
        assertChromeVisible(style: .dark)
    }

    private func assertChromeVisible(style: UIUserInterfaceStyle, testName: String = #function, line: UInt = #line) {
        let brightPhoto = photo(UIColor(white: 0.95, alpha: 1))
        let item = MediaItem(
            imageUrl: URL(string: "https://example.test/photo.jpg")!,
            preloadedImage: brightPhoto,
            altText: "A sample description of this image for the caption pill"
        )
        let vc = MediaViewerViewController(
            items: [item],
            startIndex: 0,
            dependencies: Deps(imageService: ScriptedImageService([.ready(brightPhoto)]))
        )
        vc.loadViewIfNeeded()
        vc.view.frame = CGRect(origin: .zero, size: screen)
        vc.view.layoutIfNeeded()
        revealChrome(vc.view)

        assertSnapshot(
            matching: vc,
            as: .image(drawHierarchyInKeyWindow: true, size: screen, traits: traits(style)),
            named: style == .dark ? "dark" : "light",
            testName: testName,
            line: line
        )
    }
}
