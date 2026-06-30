//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUtilKit
import Testing
import UIKit
@testable import Spud
@testable import SpudDataKit

/// Verifies the iPad timeline + Summary container wires the two columns the way
/// the detail router expects: the activity timeline roots the primary column,
/// the Summary dashboard roots the detail column, and an expanded `showDetail`
/// pushes a post OVER Summary (so the auto back button reads "Summary") rather
/// than replacing it.
@MainActor
struct ActivitySummaryReadingSplitViewControllerTests {
    private func make() -> ActivitySummaryReadingSplitViewController {
        let dependencies = FakeDependencies()
        // `ActivityViewController.init` eagerly resolves the account's
        // `lemmyService` scope, which fatal-errors for an unregistered keychain
        // id, so register a signed-out account in the in-memory DB first.
        let instance = InstanceActorId(from: "https://example.com")!
        let keychainId = dependencies.accountService.accountForSignedOut(
            forInstance: instance,
            isServiceAccount: false
        )
        return ActivitySummaryReadingSplitViewController(
            accountKeychainId: keychainId,
            accountId: 1,
            personRowId: 1,
            initialFilters: [.post, .comment, .save],
            dependencies: dependencies
        )
    }

    @Test
    func primaryIsActivity_detailRootIsSummary() {
        let vc = make()
        vc.loadViewIfNeeded()
        #expect(vc.primaryNav.viewControllers.first === vc.activityViewController)
        #expect(vc.detailNav.viewControllers.first === vc.summaryViewController)
    }

    @Test
    func showDetailExpanded_keepsSummaryAsBackTarget() {
        let vc = make()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1180, height: 820))
        window.rootViewController = vc
        window.makeKeyAndVisible()
        vc.loadViewIfNeeded()

        // On an iPhone host the window is horizontally compact regardless of its
        // size, so force the embedded split into a regular environment to
        // exercise the expanded (side-by-side) layout deterministically.
        vc.embeddedSplit.traitOverrides.horizontalSizeClass = .regular
        vc.view.frame = window.bounds
        vc.view.layoutIfNeeded()
        RunLoop.current.run(until: Date())

        #expect(vc.embeddedSplit.isCollapsed == false)

        let detail = UIViewController()
        vc.showDetail(detail)

        // Detail nav is rooted at Summary with the post on top.
        #expect(vc.detailNav.viewControllers.first === vc.summaryViewController)
        #expect(vc.detailNav.viewControllers.last === detail)
    }
}
