//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import UIKit

extension SortType {
    /// Returns the info about the sort type that will be displayed in a context menu where user can choose the desired sort type.
    var itemForMenu: (title: String, image: UIImage?) {
        switch self {
        case .active:
            return (title: "Active", image: nil)

        case .hot:
            return (title: "Hot", image: nil)

        case .new:
            return (title: "New", image: nil)

        case .old:
            return (title: "Old", image: nil)

        case .topSixHour:
            return (title: "Top Six Hour", image: nil)

        case .topTwelveHour:
            return (title: "Top Twelve Hour", image: nil)

        case .topDay:
            return (title: "Top Day", image: nil)

        case .topWeek:
            return (title: "Top Week", image: nil)

        case .topMonth:
            return (title: "Top Month", image: nil)

        case .topYear:
            return (title: "Top Year", image: nil)

        case .topAll:
            return (title: "Top All", image: nil)

        case .mostComments:
            return (title: "Most Comments", image: nil)

        case .newComments:
            return (title: "New Comments", image: nil)
        }
    }
}
