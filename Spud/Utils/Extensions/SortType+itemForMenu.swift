//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import UIKit

extension Components.Schemas.SortType {
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
        case .Active:
            return .init(title: "Active", imageSystemName: "paperplane")

        case .Hot:
            return .init(title: "Hot", imageSystemName: "flame.fill")

        case .New:
            return .init(title: "New", imageSystemName: "cursorarrow.motionlines.click")

        case .Old:
            return .init(title: "Old", imageSystemName: "text.line.last.and.arrowtriangle.forward")

        case .TopSixHour:
            return .init(title: "Top Six Hour", imageSystemName: nil)

        case .TopTwelveHour:
            return .init(title: "Top Twelve Hour", imageSystemName: nil)

        case .TopDay:
            return .init(title: "Top Day", imageSystemName: nil)

        case .TopWeek:
            return .init(title: "Top Week", imageSystemName: nil)

        case .TopMonth:
            return .init(title: "Top Month", imageSystemName: nil)

        case .TopThreeMonths:
            return .init(title: "Top Three Months", imageSystemName: nil)

        case .TopSixMonths:
            return .init(title: "Top Six Months", imageSystemName: nil)

        case .TopNineMonths:
            return .init(title: "Top Nine Months", imageSystemName: nil)

        case .TopYear:
            return .init(title: "Top Year", imageSystemName: nil)

        case .TopAll:
            return .init(title: "Top All", imageSystemName: nil)

        case .MostComments:
            return .init(title: "Most Comments", imageSystemName: "text.bubble")

        case .NewComments:
            return .init(title: "New Comments", imageSystemName: "exclamationmark.bubble")

        case .Controversial:
            return .init(title: "Controversial", imageSystemName: "person.fill.questionmark")

        case .Scaled:
            return .init(title: "Scaled", imageSystemName: "scalemass")
        }
    }
}
