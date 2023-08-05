//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

public extension VoteStatus {
    enum Action: CustomStringConvertible {
        case upvote
        case downvote

        public var description: String {
            switch self {
            case .upvote: return "upvote"
            case .downvote: return "downvote"
            }
        }
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
