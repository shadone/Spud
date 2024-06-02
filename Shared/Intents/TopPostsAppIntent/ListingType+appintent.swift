//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

@available(iOS 16.0, *)
extension Components.Schemas.ListingType {
    init(from value: IntentFeedTypeAppEnum) {
        switch value {
        case .all:
            self = .All

        case .local:
            self = .Local

        case .subscribed:
            self = .Subscribed

        case .moderatorView:
            self = .ModeratorView
        }
    }
}
