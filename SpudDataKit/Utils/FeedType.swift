//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudUtilKit

public enum FeedType: Equatable {
    case frontpage(listingType: ListingType, sortType: SortType)
    case community(communityName: String, instance: InstanceActorId, sortType: SortType)

    init?(
        sortType: SortType?,
        frontpageListingType: ListingType?,
        communityName: String?,
        communityInstanceActorId: InstanceActorId?
    ) {
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
