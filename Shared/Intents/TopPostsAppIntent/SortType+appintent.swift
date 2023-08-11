//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

@available(iOS 16.0, *)
extension SortType {
    init(from value: IntentSortTypeAppEnum) {
        switch value {
        case .active:
            self = .active
        case .hot:
            self = .hot
        case .new:
            self = .new
        case .topSixHour:
            self = .topSixHour
        case .topTwelveHour:
            self = .topTwelveHour
        case .topDay:
            self = .topDay
        case .topWeek:
            self = .topWeek
        case .topMonth:
            self = .topMonth
        case .topYear:
            self = .topYear
        case .topAll:
            self = .topAll
        case .mostComments:
            self = .mostComments
        case .newComments:
            self = .newComments
        }
    }
}
