//
// Copyright (c) 2024, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudDataKit
import SpudUtilKit

/// Snapshot row rendered in the subscriptions list. Built from a
/// `CommunityRecord` plus the parsed instance actor id derived from
/// `community.actorId`.
struct SubscriptionsCommunityRow: Equatable, Identifiable {
    let id: Int64
    let name: String
    let instanceActorId: InstanceActorId
    /// The community's federation actor id (e.g. "https://lemmy.world/c/world"),
    /// used to match against the per-account favorites set.
    let communityActorId: String
    /// Whether this community is favorited by the active account. Favorites are
    /// pinned to the top of the list and flagged with a star.
    var isFavorite: Bool = false

    /// The community's canonical web URL (`https://<instance>/c/<name>`), used
    /// for the share / copy-link context-menu actions.
    var shareURL: URL? {
        URL(string: "https://\(instanceActorId.hostWithPort)/c/\(name)")
    }
}

enum SubscriptionsViewItemType {
    case listing(Lemmy.ListingType)
    case community(SubscriptionsCommunityRow)
    /// The logged-in account's saved posts. Only offered for signed-in
    /// accounts (saved requires authentication).
    case saved
}
