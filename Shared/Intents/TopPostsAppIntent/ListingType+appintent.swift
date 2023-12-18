//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

@available(iOS 16.0, *)
extension ListingType {
    init(from value: IntentFeedTypeAppEnum) {
        switch value {
        case .all:
            self = .all

        case .local:
            self = .local

        case .subscribed:
            self = .subscribed

        case .moderatorView:
            self = .moderatorView
        }
    }
}
