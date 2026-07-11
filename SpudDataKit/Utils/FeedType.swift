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
        listingType: Components.Schemas.ListingType,
        sortType: Components.Schemas.SortType
    )

    case community(
        communityName: String,
        instance: InstanceActorId,
        sortType: Components.Schemas.SortType
    )

    /// The logged-in account's saved posts. Requires authentication; the
    /// LemmyKit `getPosts` call is made with the `.saved` filter. This feed
    /// is inherently per-account (the server scopes saved posts to the
    /// authenticated user).
    case saved(
        sortType: Components.Schemas.SortType
    )

    /// The posts this account saved for OFFLINE reading (the offline downloader
    /// stamped `post.downloadedAt`). Unlike every other case this feed is
    /// entirely LOCAL: it never calls the network — `LemmyService.fetchFeed`
    /// returns nil for it and `PostListViewModel` observes
    /// `observeDownloadedPostListRows` directly. The `sortType` is carried only
    /// for UI parity (the switcher / sort control); the rows are always ordered
    /// by `downloadedAt DESC`, so it does not affect the query.
    case downloaded(
        sortType: Components.Schemas.SortType
    )

    public var sortType: Components.Schemas.SortType {
        switch self {
        case let .frontpage(_, sortType),
             let .community(_, _, sortType),
             let .saved(sortType),
             let .downloaded(sortType):
            return sortType
        }
    }

    init?(
        sortType: Components.Schemas.SortType?,
        frontpageListingType: Components.Schemas.ListingType?,
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
