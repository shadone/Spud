//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

extension LemmyFeed {
    enum FeedType: Equatable {
        case frontpage(listingType: ListingType, sortType: SortType)

        init?(
            frontpageListingType: ListingType?,
            frontpageSortType: SortType?
        ) {
            if let frontpageListingType = frontpageListingType,
               let frontpageSortType = frontpageSortType
            {
                self = .frontpage(listingType: frontpageListingType, sortType: frontpageSortType)
                return
            }

            return nil
        }
    }

    /// The type of the feed.
    ///
    /// Describes what kind of feed we have, whether it is a frontpage for a given sort order,
    /// or a feed containing lists of a given community.
    var feedType: FeedType {
        guard
            let value = FeedType(
                frontpageListingType: frontpageListingType,
                frontpageSortType: frontpageSortType
            )
        else {
            assertionFailure("Bad feed with id '\(id)'")
            return .frontpage(listingType: .local, sortType: .active)
        }
        return value
    }
}
