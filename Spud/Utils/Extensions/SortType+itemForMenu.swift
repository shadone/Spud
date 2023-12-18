//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import UIKit

extension SortType {
    struct MenuItem {
        let title: String

        let imageSystemName: String?

        var image: UIImage? {
            guard let imageSystemName else {
                return nil
            }
            return UIImage(systemName: imageSystemName)!
        }
    }

    /// Returns the info about the sort type that will be displayed in a context menu where user can choose the desired sort type.
    var itemForMenu: MenuItem {
        switch self {
        case .active:
            return .init(title: "Active", imageSystemName: "paperplane")

        case .hot:
            return .init(title: "Hot", imageSystemName: "flame.fill")

        case .new:
            return .init(title: "New", imageSystemName: "cursorarrow.motionlines.click")

        case .old:
            return .init(title: "Old", imageSystemName: "text.line.last.and.arrowtriangle.forward")

        case .topSixHour:
            return .init(title: "Top Six Hour", imageSystemName: nil)

        case .topTwelveHour:
            return .init(title: "Top Twelve Hour", imageSystemName: nil)

        case .topDay:
            return .init(title: "Top Day", imageSystemName: nil)

        case .topWeek:
            return .init(title: "Top Week", imageSystemName: nil)

        case .topMonth:
            return .init(title: "Top Month", imageSystemName: nil)

        case .topThreeMonths:
            return .init(title: "Top Three Months", imageSystemName: nil)

        case .topSixMonths:
            return .init(title: "Top Six Months", imageSystemName: nil)

        case .topNineMonths:
            return .init(title: "Top Nine Months", imageSystemName: nil)

        case .topYear:
            return .init(title: "Top Year", imageSystemName: nil)

        case .topAll:
            return .init(title: "Top All", imageSystemName: nil)

        case .mostComments:
            return .init(title: "Most Comments", imageSystemName: "text.bubble")

        case .newComments:
            return .init(title: "New Comments", imageSystemName: "exclamationmark.bubble")

        case .controversial:
            return .init(title: "Controversial", imageSystemName: "person.fill.questionmark")

        case .scaled:
            return .init(title: "Scaled", imageSystemName: "scalemass")
        }
    }
}
