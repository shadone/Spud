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
struct SubscriptionsCommunityRow: Sendable, Equatable, Identifiable {
    let id: Int64
    let name: String
    let instanceActorId: InstanceActorId
}

enum SubscriptionsViewItemType {
    case listing(Components.Schemas.ListingType)
    case community(SubscriptionsCommunityRow)
}
