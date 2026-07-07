//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudUtilKit

public enum FeedType: Equatable, Sendable {
    case frontpage(
        listingType: Lemmy.ListingType,
        sortType: Lemmy.SortType
    )

    case community(
        communityName: String,
        instance: InstanceActorId,
        sortType: Lemmy.SortType
    )

    /// The logged-in account's saved posts. Requires authentication; the
    /// LemmyKit `getPosts` call is made with the `.saved` filter. This feed
    /// is inherently per-account (the server scopes saved posts to the
    /// authenticated user).
    case saved(
        sortType: Lemmy.SortType
    )

    public var sortType: Lemmy.SortType {
        switch self {
        case let .frontpage(_, sortType),
             let .community(_, _, sortType),
             let .saved(sortType):
            return sortType
        }
    }

    init?(
        sortType: Lemmy.SortType?,
        frontpageListingType: Lemmy.ListingType?,
        communityName: String?,
        communityInstanceActorId: InstanceActorId?,
        savedOnly: Bool = false
    ) {
        if savedOnly, let sortType {
            self = .saved(sortType: sortType)
            return
        }

        if let frontpageListingType, let sortType {
            self = .frontpage(listingType: frontpageListingType, sortType: sortType)
            return
        }

        if let communityName, let communityInstanceActorId, let sortType {
            self = .community(
                communityName: communityName,
                instance: communityInstanceActorId,
                sortType: sortType
            )
            return
        }

        return nil
    }
}
