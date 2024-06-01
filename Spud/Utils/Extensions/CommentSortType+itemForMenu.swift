//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import UIKit

extension Components.Schemas.CommentSortType {
    struct MenuItem {
        let title: String
    }

    /// Returns the info about the sort type that will be displayed in the UI where user can choose the desired sort type.
    var itemForMenu: MenuItem {
        switch self {
        case .Hot:
            return .init(title: "Hot")

        case .Top:
            return .init(title: "Top")

        case .New:
            return .init(title: "New")

        case .Old:
            return .init(title: "Old")

        case .Controversial:
            return .init(title: "Controversial")
        }
    }
}
