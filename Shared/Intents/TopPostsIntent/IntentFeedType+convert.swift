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
    init?(from feedType: FeedType) {
        switch feedType {
        case let .frontpage(listingType, _):
            switch listingType {
            case .All:
                self = .all
            case .Local:
                self = .local
            case .Subscribed:
                self = .subscribed
            case .ModeratorView:
                self = .moderatorView
            }

        case .community:
            // TODO: implement browsing community intent
            return nil

        case .saved:
            // The saved feed is per-account and auth-scoped; there is no
            // Siri intent for it.
            return nil

        case .downloaded:
            // The Downloaded (offline) feed is local-only; there is no Siri
            // intent for it.
            return nil
        }
    }
}

extension Components.Schemas.ListingType {
    init?(from intentFeedType: IntentFeedType) {
        switch intentFeedType {
        case .unknown:
            return nil

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
