//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import UIKit

extension CommentSortType {
    struct MenuItem {
        let title: String
    }

    /// Returns the info about the sort type that will be displayed in the UI where user can choose the desired sort type.
    var itemForMenu: MenuItem {
        switch self {
        case .hot:
            return .init(title: "Hot")

        case .top:
            return .init(title: "Top")

        case .new:
            return .init(title: "New")

        case .old:
            return .init(title: "Old")
        }
    }
}
