//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudDataKit
import SpudUtilKit

/// Adapts an instance-detail meta-community row (`MetaCommunityListItem`) into
/// the `SearchCommunityResult` shape `CommunityContextMenuBuilder` consumes, so
/// a meta-community row's long-press menu is byte-identical to Search's
/// `.community` result menu without a second builder/host contract.
///
/// Pure and side-effect free: every field is either carried over verbatim or
/// deterministically derived from `item`. Used by
/// `InstanceDetailViewController` at long-press time (menus are built fresh
/// per interaction, never cached).
enum MetaCommunityMenuAdapter {
    /// Builds the `SearchCommunityResult` `CommunityContextMenuBuilder.menu`
    /// needs for `item`, or `nil` if `item.communityActorId` doesn't parse to
    /// a URL with a host — the caller then skips attaching a context menu to
    /// that row rather than showing a menu with a broken Share/Copy Link/Open
    /// destination.
    ///
    /// - `subscribersText` is always `""` and `isNsfw` is always `false`:
    ///   `MetaCommunityListItem` carries neither a subscriber count nor an
    ///   NSFW flag (meta communities are surfaced by classification, not by
    ///   the directory stats Search's result carries), and
    ///   `CommunityContextMenuBuilder`'s menu never reads either field — it
    ///   only renders open/subscribe/mute/share/block/notify/favourite
    ///   actions, none of which are conditioned on subscriber count or NSFW.
    static func searchResult(for item: MetaCommunityListItem) -> SearchCommunityResult? {
        guard
            let url = URL(string: item.communityActorId),
            url.host != nil,
            let instance = InstanceActorId(from: url)
        else {
            return nil
        }

        return SearchCommunityResult(
            serverCommunityId: Lemmy.CommunityID(item.id),
            name: item.name,
            qualifiedName: "\(item.name)@\(instance.host)",
            instance: instance,
            subscribersText: "",
            iconUrl: item.iconUrl.flatMap { URL(string: $0) },
            followState: followState(for: item.subscribedState),
            isNsfw: false,
            communityUrl: item.communityActorId
        )
    }

    /// The inverse of `CommunitySubscribedState.init(followState:)`
    /// (`SpudDataKit/Services/AppDatabase/Records/Community.swift`) — no
    /// existing helper maps this direction, so this is the explicit 5-case
    /// switch mirroring that initializer case-for-case. A meta-community item
    /// already carries the RESOLVED `CommunitySubscribedState` (the observation
    /// is persisted-DB-truth, not a raw network response), so recovering a
    /// `FollowState` just to satisfy `SearchCommunityResult`'s shape loses no
    /// information: `CommunityContextMenuBuilder` immediately re-derives
    /// `CommunitySubscribedState(followState:)` from it, which is the identity
    /// transform for every case here.
    private static func followState(for subscribedState: CommunitySubscribedState) -> FollowState {
        switch subscribedState {
        case .subscribed: .accepted
        case .notSubscribed: .notFollowing
        case .pending: .pending
        case .approvalRequired: .approvalRequired
        case .denied: .denied
        }
    }
}
