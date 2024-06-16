//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import OSLog

private let logger = Logger.dataStore

public extension LemmyFeed {
    /// The type of the feed.
    ///
    /// Describes what kind of feed we have, whether it is a frontpage for a given sort order,
    /// or a feed containing lists of a given community.
    var feedType: FeedType {
        guard
            let value = FeedType(
                sortType: sortType,
                frontpageListingType: frontpageListingType,
                communityName: communityName,
                communityInstanceActorId: communityInstanceActorId
            )
        else {
            logger.assertionFailure("Bad feed with id '\(id)'")
            return .frontpage(listingType: .Local, sortType: .Active)
        }
        return value
    }
}
