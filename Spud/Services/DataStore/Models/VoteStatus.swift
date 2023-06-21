//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import os.log

enum VoteStatus {
    /// Upvoted.
    case up
    /// Downvoted.
    case down
    /// Not voted.
    case neutral

    var isUp: Bool {
        if case .up = self {
            return true
        }
        return false
    }

    var isDown: Bool {
        if case .down = self {
            return true
        }
        return false
    }

    /// Initialize from Core Data raw value.
    init(rawValue: NSNumber?) {
        guard let isUp = rawValue?.boolValue else {
            self = .neutral
            return
        }
        self = isUp ? .up : .down
    }

    /// Raw value for storing in Core Data models.
    var rawValue: NSNumber? {
        switch self {
        case .up:
            return NSNumber(booleanLiteral: true)
        case .down:
            return NSNumber(booleanLiteral: false)
        case .neutral:
            return nil
        }
    }
}

extension VoteStatus {
    enum Action {
        case upvote
        case downvote
    }

    /// The action to take if the user interacts with a vote button.
    ///
    /// E.g. if the post is already upvoted and the user pressed upvote button,
    /// the effective action is to remote the vote aka "unvote".
    func effectiveAction(for action: Action) -> ScoreAction {
        switch (self, action) {
        case (.up, .upvote),
             (.down, .downvote):
            return .unvote
        case (_, .upvote):
            return .upvote
        case (_, .downvote):
            return .downvote
        }
    }

    func voteCountChange(for action: Action) -> Int64 {
        switch (self, action) {
        case (.neutral, .upvote),
             (.down, .downvote):
            return 1
        case (.neutral, .downvote),
             (.up, .upvote):
            return -1
        case (.down, .upvote):
            return 2
        case (.up, .downvote):
            return -2
        }
    }
}
