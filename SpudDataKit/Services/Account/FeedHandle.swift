//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

/// Lightweight reference to a feed that decouples callers from the underlying
/// storage. Carries everything view models and the widget need: the
/// stable `feedKey` (used by GRDB observations and the LemmyService API)
/// and the `feedType` (used to render the navigation title and sort menu).
public struct FeedHandle: Sendable, Equatable {
    public let feedKey: String
    public let feedType: FeedType

    public init(feedKey: String, feedType: FeedType) {
        self.feedKey = feedKey
        self.feedType = feedType
    }
}
