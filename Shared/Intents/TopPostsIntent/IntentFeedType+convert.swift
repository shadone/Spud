//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Intents
import LemmyKit
import SpudDataKit

extension IntentFeedType {
    init(from feedType: FeedType) {
        switch feedType {
        case let .frontpage(listingType, _):
            switch listingType {
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
}

extension ListingType {
    init?(from intentFeedType: IntentFeedType) {
        switch intentFeedType {
        case .unknown:
            return nil

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
