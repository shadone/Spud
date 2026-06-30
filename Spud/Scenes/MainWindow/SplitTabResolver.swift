//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// Where a detail push (a post, person, or community opened from somewhere in
/// the UI) should land, given the tab the user is currently in.
///
/// On iPad multiple tabs can host a split-view reading context, so "show this
/// detail" is no longer "push onto the Posts split" — it must land in whichever
/// context is active so Back returns the user to where they were and the
/// primary column (e.g. the community feed) stays visible.
enum DetailRouteTarget {
    /// The Posts tab's own split view is selected — route via the split's
    /// collapsed/expanded detail handling.
    case postsSplit
    /// A community reading split (a plain container embedding a child split, not
    /// a `UISplitViewController`) is on top of the selected tab's nav stack —
    /// route detail into its secondary column via `showDetail(_:)`.
    case community(CommunityReadingSplitViewController)
    /// A plain single-column tab — push onto its navigation stack.
    case plainNav(UINavigationController)
    /// No usable navigation context (e.g. a cold deep link before any tab UI is
    /// in place) — the caller falls back to the Posts tab.
    case none
}

/// Classifies the currently selected tab into the `DetailRouteTarget` the
/// detail router should use. Pure and side-effect free so it can be unit tested
/// without a live tab-bar / window.
///
/// Detection order matters: the Posts split is matched by identity first; a
/// community reading split is detected by its **concrete type** sitting on top
/// of a tab's navigation stack (it is a container view controller, not a
/// `UISplitViewController`, so a type cast to `UISplitViewController` would miss
/// it); any other navigation controller is a plain push target.
enum SplitTabResolver {
    static func target(
        for selected: UIViewController?,
        postsSplit: UISplitViewController
    ) -> DetailRouteTarget {
        if selected === postsSplit {
            return .postsSplit
        }
        if let nav = selected as? UINavigationController {
            if let community = nav.viewControllers.last as? CommunityReadingSplitViewController {
                return .community(community)
            }
            return .plainNav(nav)
        }
        return .none
    }
}
