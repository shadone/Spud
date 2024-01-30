//
// Copyright (c) 2024, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudDataKit

enum SubscriptionsViewItemType {
    case listing(ListingType)
    case community(LemmyCommunityInfo)
}
