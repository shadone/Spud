//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
import UIKit
@testable import Spud

/// Guards the alt-text sheet's vertical constraint chain
/// (``ShareAsImageAltTextViewController``).
///
/// The editing card is a scroll-enabled `UITextView`, so it reports NO intrinsic
/// content height — its height exists only if the constraint chain from the top
/// of the sheet to the bottom is fully determined. It once was not: the footnote
/// was pinned to the bottom by an INEQUALITY, nothing else constrained the text
/// view's height, and Auto Layout resolved the only free variable to zero. The
/// sheet shipped showing nothing but the grey footnote, with a green build and a
/// green test suite, because no test measured the card.
///
/// So this suite measures the card, and it does it on the REAL presentation: the
/// controller is presented as the same `.pageSheet` (medium + large detents) that
/// `ShareAsImageViewController.presentAltTextEditor()` builds, not hosted as a
/// window root — hosting as a root sidesteps the sheet's own geometry, which is
/// precisely what squeezes this layout.
///
/// The window is attached to the host scene and made VISIBLE but deliberately
/// **not key**: a real (non-zero) safe area only reaches the hierarchy through a
/// scene-attached, on-screen window, and stealing key-window status would leak
/// into snapshot suites that render via `drawHierarchyInKeyWindow`. Same pattern
/// as `ComposerGlassContentInsetTests`.
///
/// Serialized because both tests attach a window to the single shared host
/// scene and pump the run loop to settle layout — that pump lets another
/// `@MainActor` test's work interleave, and two live presentations on one scene
/// measure each other's geometry (observed: a second presentation laying out at
/// zero width).
@MainActor
@Suite(.serialized)
struct ShareAsImageAltTextLayoutTests {
    // MARK: - Tests

    @Test
    func presentedAsASheet_theEditingCardFillsTheSpaceAboveTheFootnote() async throws {
        let editor = ShareAsImageAltTextViewController(
            currentText: "A screenshot of the post, rendered as a share card.",
            isAuto: true,
            autoText: "A screenshot of the post, rendered as a share card."
        )
        let harness = try await SheetHarness(presenting: editor)
        defer { harness.tearDown() }

        let textView = try #require(harness.firstChild(of: UITextView.self, in: editor.view))
        let footnote = try #require(harness.firstChild(of: UILabel.self, in: editor.view))

        // The precondition that makes the height a free variable at all: a
        // scrolling UITextView contributes no intrinsic content height, so
        // nothing but the constraint chain can size it. If a future change turns
        // scrolling off, this test stops discriminating and needs rethinking
        // rather than silently passing.
        #expect(textView.isScrollEnabled)

        #expect(editor.view.bounds.height > 0, "the sheet itself must have laid out for this test to mean anything")

        // The bug: this was 0.
        #expect(textView.bounds.height > 0)
        #expect(textView.bounds.height >= ShareAsImageAltTextViewController.minimumCardHeight)

        // The card must actually fill the sheet, not sit as a small box at the
        // top: everything between the card's bottom and the sheet's bottom is
        // the 12pt gap, the footnote, and the 16pt bottom margin.
        let available = editor.view.safeAreaLayoutGuide.layoutFrame
        let slack = available.maxY - footnote.frame.maxY
        #expect(slack >= 0, "the footnote must not hang below the safe area")
        #expect(slack < 20, "the card should absorb the leftover space, not leave a gap under the footnote")

        // Reading order: card, then its footnote, and the two must not overlap.
        #expect(footnote.frame.minY >= textView.frame.maxY)
        #expect(footnote.frame.height > 0)
    }

    @Test
    func theCardIsWideEnoughToRead() async throws {
        let editor = ShareAsImageAltTextViewController(currentText: "Alt text.", isAuto: false, autoText: "Auto.")
        let harness = try await SheetHarness(presenting: editor)
        defer { harness.tearDown() }

        let textView = try #require(harness.firstChild(of: UITextView.self, in: editor.view))
        #expect(textView.bounds.width > 0)
        // The card spans the sheet's layout margins.
        let margins = editor.view.layoutMarginsGuide.layoutFrame
        #expect(abs(textView.frame.minX - margins.minX) < 0.5)
        #expect(abs(textView.frame.maxX - margins.maxX) < 0.5)
    }

    // MARK: - Harness

    /// Presents a controller exactly the way `presentAltTextEditor()` does — a
    /// navigation controller in a medium/large page sheet — on a scene-attached,
    /// visible, never-key window.
    @MainActor
    private struct SheetHarness {
        let window: UIWindow
        let navigationController: UINavigationController
        let presenter: UIViewController

        init(presenting editor: UIViewController) async throws {
            navigationController = UINavigationController(rootViewController: editor)
            navigationController.modalPresentationStyle = .pageSheet
            if let sheet = navigationController.sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.prefersGrabberVisible = true
            }

            let scene = try #require(
                UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .first { $0.activationState == .foregroundActive },
                "the test host must have a foreground scene to supply a real safe area"
            )
            let hostWindow = UIWindow(windowScene: scene)
            hostWindow.frame = scene.screen.bounds
            let host = UIViewController()
            host.view.backgroundColor = .systemBackground
            hostWindow.rootViewController = host
            // Visible, never key - see the suite doc comment.
            hostWindow.isHidden = false
            window = hostWindow
            presenter = host

            host.present(navigationController, animated: false)
            // A modal presentation is not complete when `present` returns, even
            // unanimated - it finishes on a later main-runloop turn, and until it
            // does the sheet has no geometry to measure. Poll rather than pump a
            // fixed number of runloop turns: how many turns that takes is a
            // property of the machine's load, not of the layout under test.
            let editorView = editor.view!
            await waitUntil("the alt-text sheet to be presented and sized") {
                hostWindow.layoutIfNeeded()
                return editorView.window != nil && editorView.bounds.height > 0
            }
            settle()
        }

        /// Dismisses BEFORE dropping the window: tearing the root controller out
        /// from under a live presentation leaves the scene in a half-presented
        /// state ("Unbalanced calls to begin/end appearance transitions"), and
        /// the NEXT test's sheet then lays out at zero size.
        func tearDown() {
            presenter.dismiss(animated: false)
            settle()
            window.isHidden = true
            window.rootViewController = nil
        }

        func settle() {
            window.layoutIfNeeded()
            RunLoop.current.run(until: Date())
            window.layoutIfNeeded()
        }

        /// Direct children only: the two views under test are both direct
        /// subviews of the controller's view, and a recursive search would
        /// happily return one of `UITextView`'s private internal labels.
        func firstChild<T: UIView>(of _: T.Type, in view: UIView) -> T? {
            view.subviews.compactMap { $0 as? T }.first
        }
    }
}
