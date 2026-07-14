//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit

/// The single source of truth for the community subscribe button's title + SF
/// Symbol per ``CommunitySubscribedState``. Both `CommunityHeaderView` (the
/// Community screen's prominent button) and `SearchCommunityCell` (Search's
/// inline row button) render the same 5-state vocabulary for the same
/// persisted state — this helper keeps that copy defined exactly once so the
/// two surfaces can never drift apart (the DRY rule this fix exists to
/// restore: Search used to render its own lossy 2-state label instead of
/// this vocabulary).
enum CommunitySubscribeButtonLabel {
    /// The button's primary title for `state`.
    static func title(for state: CommunitySubscribedState) -> String {
        switch state {
        case .notSubscribed, .denied:
            // `.denied` still offers to (re-)subscribe; callers that want to
            // surface the prior rejection add their own subtitle/accessibility
            // text alongside this title (see `CommunityHeaderView`).
            NSLocalizedString("Subscribe", comment: "Community subscribe button")
        case .subscribed:
            NSLocalizedString("Subscribed", comment: "Community unsubscribe button")
        case .pending:
            NSLocalizedString("Pending", comment: "Community pending-subscription button")
        case .approvalRequired:
            NSLocalizedString(
                "Requested",
                comment: "Community subscribe button when the community requires moderator approval and the follow request is awaiting a decision"
            )
        }
    }

    /// The SF Symbol name shown alongside the title for `state`.
    static func symbol(for state: CommunitySubscribedState) -> String {
        switch state {
        case .notSubscribed, .denied:
            "plus"
        case .subscribed:
            "checkmark"
        case .pending:
            "clock"
        case .approvalRequired:
            "hourglass"
        }
    }
}
