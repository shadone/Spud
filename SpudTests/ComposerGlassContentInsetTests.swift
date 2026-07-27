//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudDataKit
import SpudUtilKit
import Testing
import UIKit
@testable import Spud

// MARK: - Test doubles

private final class NullImageService: ImageServiceType, @unchecked Sendable {
    func fetch(_: URL, thumbnail _: URL?) -> AsyncStream<ImageLoadingState> {
        AsyncStream { $0.finish() }
    }
}

@MainActor
private struct ComposerInsetDependencies: HasAccountService, HasAlertService, HasImageService {
    let accountService: AccountServiceType
    let alertService: AlertServiceType
    let imageService: ImageServiceType

    init(appDatabase: AppDatabase) {
        accountService = AccountService(appDatabase: appDatabase)
        alertService = AlertService()
        imageService = NullImageService()
    }
}

// MARK: - Tests

/// Guards the one place in the app where a repinned "content flows under the
/// glass bar" screen puts its scroll views TWO levels down.
///
/// `ComposerViewController` pins its `MarkdownEditorView` container to
/// `view.topAnchor` (not the safe area) so the draft scrolls under the
/// translucent bar. The container is a plain `UIView`, so nothing rests the
/// content below the bar by itself — the screen depends on the write-mode
/// `UITextView`'s **`.automatic`** content inset adjustment converting the
/// inherited top safe area into a resting `adjustedContentInset`.
///
/// That conversion is the fragile part, and the fragility is specific to an
/// EMPTY draft: `UIScrollView.ContentInsetAdjustmentBehavior.scrollableAxes`
/// adjusts only along an axis that is actually scrollable, and an empty draft's
/// text view is not vertically scrollable (`contentSize.height` is far below its
/// frame, and it sets no `alwaysBounce*`). Measured on iPhone 17 Pro / iOS 26.3:
/// under `.automatic` the top inset is the full bar height (116), while the same
/// view forced to `.scrollableAxes` reports 0 and the caret lands ~105pt behind
/// the bar. So a change that switches the behaviour, or that re-parents the
/// editor such that UIKit no longer treats the text view as the controller's
/// content view, would silently hide the caret behind the navigation bar with a
/// still-green test suite. Hence this test.
///
/// The window is attached to the host scene and made VISIBLE but deliberately
/// **not key**: a real (non-zero) safe area only reaches the hierarchy through a
/// scene-attached, on-screen window, and stealing key-window status would leak
/// into snapshot suites that render via `drawHierarchyInKeyWindow`.
@MainActor
struct ComposerGlassContentInsetTests {
    /// Depth-first search for the editor (`ComposerViewController.editorView` is
    /// private).
    private func findEditor(in view: UIView) -> MarkdownEditorView? {
        if let editor = view as? MarkdownEditorView { return editor }
        for subview in view.subviews {
            if let found = findEditor(in: subview) { return found }
        }
        return nil
    }

    private func settle(_ window: UIWindow) {
        window.layoutIfNeeded()
        RunLoop.current.run(until: Date())
        window.layoutIfNeeded()
    }

    @Test
    func emptyDraft_writeTextViewRestsBelowTheNavigationBar() throws {
        let appDatabase = try AppDatabase.inMemory()
        let dependencies = ComposerInsetDependencies(appDatabase: appDatabase)
        let instance = try #require(InstanceActorId(from: "https://example.com"))
        let keychainId = dependencies.accountService.accountForSignedOut(
            forInstance: instance,
            isServiceAccount: false
        )
        let composer = ComposerViewController(
            target: .postReply(serverPostId: Lemmy.PostID(1)),
            accountKeychainId: keychainId,
            dependencies: dependencies
        )
        let nav = UINavigationController(rootViewController: composer)

        let scene = try #require(
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive },
            "the test host must have a foreground scene to supply a real safe area"
        )
        let window = UIWindow(windowScene: scene)
        window.frame = scene.screen.bounds
        window.rootViewController = nav
        // Visible, never key - see the suite doc comment.
        window.isHidden = false
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        settle(window)
        let editor = try #require(findEditor(in: composer.view))
        editor.text = ""
        settle(window)

        let textView = editor.textView
        let navBarMaxY = nav.navigationBar.convert(nav.navigationBar.bounds, to: window).maxY
        #expect(navBarMaxY > 0, "the navigation bar must occupy real space for this test to mean anything")

        // The precondition that makes this the interesting case: with an empty
        // draft the write text view is NOT vertically scrollable, so a
        // `.scrollableAxes` behaviour would contribute no top inset at all. If a
        // future change makes it always scrollable (e.g. by setting
        // `alwaysBounceVertical`), this test stops discriminating and the
        // assertions below need rethinking rather than silently passing.
        #expect(textView.contentSize.height < textView.bounds.height)
        #expect(textView.alwaysBounceVertical == false)
        #expect(textView.contentInsetAdjustmentBehavior == .automatic)

        // The actual guarantee: content rests exactly below the bar.
        #expect(textView.adjustedContentInset.top == navBarMaxY)

        // And the user-visible consequence: the insertion point is below the bar,
        // not hidden behind it. (The comment composer sets no placeholder text,
        // so the caret is what an empty draft actually shows.)
        let start = try #require(textView.position(from: textView.beginningOfDocument, offset: 0))
        let caretInWindow = textView.convert(textView.caretRect(for: start), to: window)
        #expect(caretInWindow.minY >= navBarMaxY)
    }
}
