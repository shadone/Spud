//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Intents
import LemmyKit
import SpudDataKit

extension IntentSortType {
    init(from sortType: Components.Schemas.SortType) {
        switch sortType {
        case .Active:
            self = .active
        case .Hot:
            self = .hot
        case .New:
            self = .new
        case .Old:
            // we are not exposing Old sort to the widget configuration
            self = .unknown
        case .TopSixHour:
            self = .topSixHour
        case .TopTwelveHour:
            self = .topTwelveHour
        case .TopDay:
            self = .topDay
        case .TopWeek:
            self = .topWeek
        case .TopMonth:
            self = .topMonth
        case .TopYear:
            self = .topYear
        case .TopAll:
            self = .topAll
        case .MostComments:
            self = .mostComments
        case .NewComments:
            self = .newComments
        case .TopThreeMonths:
            self = .topThreeMonths
        case .TopSixMonths:
            self = .topSixMonths
        case .TopNineMonths:
            self = .topNineMonths
        case .Controversial:
            self = .controversial
        case .Scaled:
            self = .scaled
        }
    }
}

extension Components.Schemas.SortType {
    init?(from intentSortType: IntentSortType) {
        switch intentSortType {
        case .unknown:
            return nil
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
        case .topThreeMonths:
            self = .TopThreeMonths
        case .topSixMonths:
            self = .TopSixMonths
        case .controversial:
            self = .Controversial
        case .scaled:
            self = .Scaled
        case .topNineMonths:
            self = .TopNineMonths
        }
    }
}
