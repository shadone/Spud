//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

@available(iOS 16.0, *)
extension Components.Schemas.SortType {
    init(from value: IntentSortTypeAppEnum) {
        switch value {
        case .active:
            self = .Active
        case .hot:
            self = .Hot
        case .new:
            self = .New
        case .topSixHour:
            self = .TopSixHour
        case .topTwelveHour:
            self = .TopTwelveHour
        case .topDay:
            self = .TopDay
        case .topWeek:
            self = .TopWeek
        case .topMonth:
            self = .TopMonth
        case .topYear:
            self = .TopYear
        case .topAll:
            self = .TopAll
        case .mostComments:
            self = .MostComments
        case .newComments:
            self = .NewComments
        }
    }
}
