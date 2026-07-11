//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

extension Lemmy.CommunityView {
    /// A fake neutral ``LemmyKit/CommunityView``. The community's counts now live on
    /// the ``LemmyKit/Community`` itself; the viewer's follow state rides on
    /// `communityActions`. `subscribed` keeps taking the v3 `SubscribedType` for
    /// call-site stability and is mapped to the neutral ``LemmyKit/FollowState``.
    static func fake(
        community: Lemmy.Community = .fake,
        subscribed: Lemmy.SubscribedType = .NotSubscribed,
        canMod: Bool = false
    ) -> Lemmy.CommunityView {
        let followState: FollowState = switch subscribed {
        case .Subscribed: .accepted
        case .Pending: .pending
        default: .notFollowing
        }
        return .init(
            community: community,
            communityActions: CommunityActions(followState: followState),
            canMod: canMod
        )
    }

    /// A fake neutral ``LemmyKit/CommunityView`` carrying an explicit neutral
    /// ``LemmyKit/FollowState``. Unlike the `subscribed:` overload (which takes a
    /// v3 `SubscribedType` that cannot represent the v4-only states), this drives
    /// `.approvalRequired` / `.denied` directly for v4 follow-state tests.
    static func fake(
        community: Lemmy.Community = .fake,
        followState: FollowState,
        canMod: Bool = false
    ) -> Lemmy.CommunityView {
        .init(
            community: community,
            communityActions: CommunityActions(followState: followState),
            canMod: canMod
        )
    }
}
