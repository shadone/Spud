//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import SpudUtilKit
import UIKit

/// iPad reading context for the account's Activity: the activity timeline in the
/// primary column, the Summary dashboard pinned in the secondary. Collapses to a
/// single-column push stack in compact (iPhone / iPad multitasking), where the
/// timeline shows its own inline footprint rail and Summary is reached through
/// the nav-bar button instead.
///
/// ## Containment mechanic (mirrors `CommunityReadingSplitViewController`)
///
/// `UISplitViewController` cannot be pushed onto a navigation controller, so this
/// is a plain container view controller that **embeds a child
/// `UISplitViewController`** and is itself pushable onto the Account tab's
/// navigation stack. The hosting nav bar is hidden while this screen is on
/// display (otherwise a stacked double bar appears over the primary column) and
/// restored on pop (see `viewWillAppear` / `viewWillDisappear`). Return to the
/// Account screen is exposed through a visible "Account" back button injected onto
/// the primary column's root (see the `UINavigationControllerDelegate`
/// conformance), complementing the hosting nav controller's left-edge back swipe.
///
/// ## Difference from the Community split
///
/// The Community split's detail column starts on an empty placeholder and each
/// shown post **replaces** the column. Here the detail column is rooted at the
/// Summary dashboard: at regular width Summary is always visible, and a tapped
/// post/comment is **pushed over** Summary (`showDetail(_:)`) so the auto back
/// button reads "Summary" and only one detail is ever shown. On collapse the
/// detail stack is reset back to Summary alone and the timeline takes the merged
/// column (`UISplitViewControllerDelegate` below); the timeline's pinned state is
/// toggled so it shows/hides its inline footprint rail + Summary button to match.
final class ActivitySummaryReadingSplitViewController: UIViewController {
    typealias Dependencies =
        ActivityViewController.Dependencies &
        SummaryViewController.Dependencies

    /// The embedded two-column split. A child VC (see the containment note) — it
    /// must not be pushed onto a navigation controller directly.
    let embeddedSplit = UISplitViewController(style: .doubleColumn)

    /// The primary column's nav stack, rooted at the activity timeline. Also the
    /// `.compact` column, so a collapse merges into this same stack.
    let primaryNav: UINavigationController

    /// The secondary column's nav stack, rooted at the Summary dashboard. Unlike
    /// the Community split, `showDetail(_:)` pushes ONTO this stack (over Summary)
    /// rather than replacing the column, so Summary stays the back target.
    let detailNav: UINavigationController

    /// The activity timeline shown in the primary column.
    let activityViewController: ActivityViewController

    /// The Summary dashboard pinned in the secondary column (regular width), and
    /// re-rooted as the detail stack on collapse.
    let summaryViewController: SummaryViewController

    init(
        accountKeychainId: String,
        accountId: Int64,
        personRowId: Int64?,
        initialFilters: Set<ActivityFilterType>,
        asOf: Date = Date(),
        dependencies: Dependencies
    ) {
        activityViewController = ActivityViewController(
            accountKeychainId: accountKeychainId,
            initialFilters: initialFilters,
            dependencies: dependencies
        )
        summaryViewController = SummaryViewController(
            accountId: accountId,
            personRowId: personRowId,
            asOf: asOf,
            dependencies: dependencies
        )
        primaryNav = UINavigationController(rootViewController: activityViewController)
        detailNav = UINavigationController(rootViewController: summaryViewController)

        super.init(nibName: nil, bundle: nil)

        primaryNav.enableForwardNavigationGesture()
        detailNav.enableForwardNavigationGesture()

        embeddedSplit.setViewController(primaryNav, for: .primary)
        embeddedSplit.setViewController(detailNav, for: .secondary)
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
        // Embed the split as a child so this container is pushable onto the Account
        // nav stack (a UISplitViewController itself is not).
        add(child: embeddedSplit)
        addSubviewWithEdgeConstraints(child: embeddedSplit)
        // Complete the UIKit containment handshake: `add(child:)` calls
        // `willMove(toParent:)` but NOT `didMove(toParent:)`.
        embeddedSplit.didMove(toParent: self)

        // Inject the "Account" back button onto the primary column's root, and
        // own the collapse/expand transitions.
        primaryNav.delegate = self
        embeddedSplit.delegate = self

        // Seed the pinned state from the resolved column layout — the
        // collapse/expand delegate callbacks do NOT fire for the initial state
        // (an iPad launches already expanded; an iPhone already collapsed).
        activityViewController.setSummaryIsPinned(!embeddedSplit.isCollapsed)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Hide the hosting Account nav bar so the only chrome on screen is each
        // column's own bar (no stacked double bar). See the containment note.
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Restore the Account screen's chrome only when genuinely navigating away.
        // Guard against modal-presentation / dismissal cycles that also fire
        // viewWillDisappear (e.g. presenting a sheet) — `isMovingFromParent` is
        // true only on an actual nav-stack pop, `isBeingDismissed` on a modal
        // dismissal of the hosting nav controller.
        guard isMovingFromParent || isBeingDismissed else { return }
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    /// Shows a post/comment detail. Collapsed: pushes onto the primary stack (the
    /// iPhone shape). Expanded: pushes over Summary in the detail column so the
    /// auto back button reads "Summary" and only one detail is ever shown.
    func showDetail(_ viewController: UIViewController) {
        if embeddedSplit.isCollapsed {
            primaryNav.pushViewController(viewController, animated: true)
        } else {
            detailNav.setViewControllers([summaryViewController, viewController], animated: true)
        }
    }

    // MARK: - Back button

    /// Builds the "Account" leading button that mimics the system back button
    /// appearance (chevron + label) and pops the hosting nav stack back to the
    /// Account screen. Injected onto the primary column's root VC via
    /// `UINavigationControllerDelegate`.
    ///
    /// Built as a standard `UIBarButtonItem` (no `customView`) so UIKit applies
    /// the `accessibilityLabel` on the item itself and sizes it to the HIG 44 pt
    /// minimum tap target.
    private func makeBackButton() -> UIBarButtonItem {
        let action = UIAction { [weak self] _ in
            self?.navigationController?.popViewController(animated: true)
        }
        let item = UIBarButtonItem(
            title: "Account",
            image: UIImage(systemName: "chevron.backward"),
            primaryAction: action,
            menu: nil
        )
        item.accessibilityLabel = "Back to Account"
        return item
    }
}

// MARK: - UINavigationControllerDelegate

extension ActivitySummaryReadingSplitViewController: UINavigationControllerDelegate {
    func navigationController(
        _ navigationController: UINavigationController,
        willShow viewController: UIViewController,
        animated _: Bool
    ) {
        // Inject ONLY on the root (the timeline), never on a post pushed deeper
        // into the collapsed primary stack — otherwise "Account" would stamp over
        // the post's own back button and pop the whole container.
        guard navigationController.viewControllers.first === viewController else { return }
        // The timeline sets only the right bar button (Summary), so the leading
        // slot is unclaimed; inject only if so.
        guard viewController.navigationItem.leftBarButtonItem == nil else { return }
        viewController.navigationItem.leftBarButtonItem = makeBackButton()
    }
}

// MARK: - UISplitViewControllerDelegate

extension ActivitySummaryReadingSplitViewController: UISplitViewControllerDelegate {
    func splitViewControllerDidExpand(_: UISplitViewController) {
        // Summary is now pinned in the detail column: suppress the timeline's
        // inline footprint rail + Summary nav button.
        activityViewController.setSummaryIsPinned(true)
    }

    func splitViewControllerDidCollapse(_: UISplitViewController) {
        // Summary is no longer pinned: the timeline restores its inline rail +
        // Summary button.
        activityViewController.setSummaryIsPinned(false)
        // Drop any post that was pushed over Summary so a later re-expand shows
        // Summary again, and the merged primary stack shows only the timeline.
        detailNav.setViewControllers([summaryViewController], animated: false)
    }

    func splitViewController(
        _: UISplitViewController,
        topColumnForCollapsingToProposedTopColumn _: UISplitViewController.Column
    ) -> UISplitViewController.Column {
        // Collapse to the timeline, not Summary.
        .primary
    }
}
