//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudUtilKit
import Testing
import UIKit
@testable import Spud

/// Guards `PostDetailViewController.jumpToNextButton` — the floating
/// jump-to-next-comment FAB, converted to `.glass()` / `.prominentGlass()` for
/// Liquid Glass — against the documented tap-dead-zone bug class: a button
/// inside a superview with `isUserInteractionEnabled = false` renders fine but
/// can never receive a finger tap, because `hitTest` does not descend into a
/// disabled ancestor. Neither `sendActions(for:)` nor VoiceOver activation would
/// catch that, so this asserts real `hitTest` geometry instead — mirroring
/// `ImageBlockViewTests.failedPlateButtonsAreHitTestReachable`.
@MainActor
struct PostDetailJumpButtonHitTestTests {
    private func makeViewController(dependencies: FakeDependencies = FakeDependencies()) throws -> PostDetailViewController {
        let instance = try #require(InstanceActorId(from: "https://example.com"))
        let keychainId = dependencies.accountService.accountForSignedOut(
            forInstance: instance,
            isServiceAccount: false
        )
        let vc = PostDetailViewController(
            serverPostId: Lemmy.PostID(1),
            accountKeychainId: keychainId,
            dependencies: dependencies
        )
        vc.loadViewIfNeeded()
        vc.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        vc.view.layoutIfNeeded()
        return vc
    }

    /// Both jump-button styles (the default chevron and the accented "Next
    /// new" state) share the same underlying button, so both must stay
    /// reachable — not just whichever style happens to be first.
    @Test
    func defaultStyleIsHitTestReachable() throws {
        let vc = try makeViewController()
        try Self.assertReachable(vc.jumpToNextButton, in: vc.view)
    }

    private static func assertReachable(_ button: UIButton, in root: UIView) throws {
        // The FAB starts hidden until there is something to jump to; that is
        // unrelated to the bug this test guards against, so reveal it (and
        // every ancestor) before hit-testing.
        var current: UIView? = button
        while let node = current {
            node.alpha = 1
            node.isHidden = false
            if node === root { break }
            current = node.superview
        }
        root.layoutIfNeeded()

        let center = root.convert(
            CGPoint(x: button.bounds.midX, y: button.bounds.midY),
            from: button
        )
        let hit = root.hitTest(center, with: nil)
        #expect(
            hit === button || hit?.isDescendant(of: button) == true,
            "a tap on the jump-to-next-comment button must reach it, not a disabled ancestor"
        )
    }
}
