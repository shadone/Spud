//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import SpudDataKit
import SpudUtilKit
import UIKit

/// iPad reading context for a single community: the community screen (header +
/// feed) in the primary column, the selected post in the secondary. Collapses
/// to a single-column push stack in compact (iPhone / iPad multitasking),
/// matching the pre-split behavior.
///
/// ## Containment mechanic (validated on the spike, Task 7)
///
/// This screen is pushed onto the Communities tab's navigation stack. The
/// natural shape — subclass `UISplitViewController` and push it directly — is
/// **rejected by UIKit**: `pushViewController` no-ops with
/// "Split View Controllers cannot be pushed to a Navigation Controller". So this
/// is instead a plain container view controller that **embeds a child
/// `UISplitViewController`** and is itself pushable. (Child split view
/// controllers are a supported UIKit pattern; the column layout and the
/// size-class-driven collapse work unchanged when the split is a child.)
///
/// The second sharp edge is the navigation bar. The pushed container is hosted
/// by the Communities `UINavigationController`, whose bar renders ABOVE each
/// embedded column's own bar — a stacked double bar on the primary side (an
/// empty "< Communities" bar over the community title/sort/overflow bar). The
/// fix, confirmed on an iPad sim, is to **hide the hosting Communities nav bar
/// while this screen is on display and restore it on pop** (see `viewWillAppear`
/// / `viewWillDisappear`). Each column then shows exactly one bar. Return to the
/// Communities list is the standard left-edge back swipe on the hosting
/// navigation controller — its `interactivePopGestureRecognizer` stays active
/// with the bar hidden, and the primary column's own back/forward edge gestures
/// only engage once a post has been pushed into the stack (collapsed), so there
/// is no left-edge conflict at the community root.
///
/// `.compact` reuses the primary nav stack, so an iPad window that shrinks to a
/// compact width (Slide Over / Split View multitasking) collapses to the single
/// community feed, with any selected post pushed onto the same stack — exactly
/// the iPhone shape. On iPhone the split is never built:
/// `SubscriptionsViewController` gates on the horizontal size class and pushes
/// `CommunityOrLoadingViewController` directly in compact.
final class CommunityReadingSplitViewController: UIViewController {
    typealias Dependencies =
        CommunityOrLoadingViewController.Dependencies &
        PostDetailOrEmptyViewController.Dependencies

    /// The embedded two-column split. A child VC (see the containment note) — it
    /// must not be pushed onto a navigation controller directly.
    private let embeddedSplit = UISplitViewController(style: .doubleColumn)

    private let primaryNav = UINavigationController()

    /// The secondary column's navigation stack. Exposed so the router (Task 8)
    /// can inspect / drive the detail column directly.
    let detailNavigationController = UINavigationController()

    init(
        communityName: String,
        instance: InstanceActorId,
        accountKeychainId: String,
        dependencies: Dependencies
    ) {
        super.init(nibName: nil, bundle: nil)

        let communityVC = CommunityOrLoadingViewController(
            communityName: communityName,
            instance: instance,
            accountKeychainId: accountKeychainId,
            dependencies: dependencies
        )
        primaryNav.setViewControllers([communityVC], animated: false)
        primaryNav.enableForwardNavigationGesture()

        let empty = PostDetailOrEmptyViewController(
            accountKeychainId: accountKeychainId,
            dependencies: dependencies
        )
        detailNavigationController.setViewControllers([empty], animated: false)
        detailNavigationController.enableForwardNavigationGesture()

        embeddedSplit.setViewController(primaryNav, for: .primary)
        embeddedSplit.setViewController(detailNavigationController, for: .secondary)
        embeddedSplit.setViewController(primaryNav, for: .compact)

        embeddedSplit.preferredDisplayMode = .oneBesideSecondary
        embeddedSplit.preferredSplitBehavior = .tile
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Embed the split as a child so this container is pushable onto the
        // Communities nav stack (a UISplitViewController itself is not).
        add(child: embeddedSplit)
        addSubviewWithEdgeConstraints(child: embeddedSplit)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Hide the hosting Communities nav bar so the only chrome on screen is
        // each column's own bar (no stacked double bar). See the containment
        // note above.
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Restore the Communities list chrome (large title, search, sort menu)
        // as we pop back to it.
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    /// Shows a post in the secondary column (or pushes onto the primary stack
    /// when collapsed), mirroring `MainWindow.pushDetail`. Consumed by the
    /// community-feed post-tap router (Task 8).
    func showDetail(_ viewController: UIViewController) {
        if embeddedSplit.isCollapsed {
            primaryNav.pushViewController(viewController, animated: true)
        } else {
            let nav = UINavigationController(rootViewController: viewController)
            nav.enableForwardNavigationGesture()
            embeddedSplit.showDetailViewController(nav, sender: self)
        }
    }
}
