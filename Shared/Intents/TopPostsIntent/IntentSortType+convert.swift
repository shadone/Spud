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
    init(from sortType: SortType) {
        switch sortType {
        case .active:
            self = .active
        case .hot:
            self = .hot
        case .new:
            self = .new
        case .old:
            // we are not exposing Old sort to the widget configuration
            self = .unknown
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

extension SortType {
    init?(from intentSortType: IntentSortType) {
        switch intentSortType {
        case .unknown:
            return nil
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
