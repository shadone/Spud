//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

public enum FeedType: Equatable {
    case frontpage(listingType: ListingType, sortType: SortType)

    init?(
        frontpageListingType: ListingType?,
        sortType: SortType?
    ) {
        if let frontpageListingType, let sortType {
            self = .frontpage(listingType: frontpageListingType, sortType: sortType)
            return
        }

        return nil
    }
}
