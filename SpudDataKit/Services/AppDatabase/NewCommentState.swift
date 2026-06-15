//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Pure, UIKit-free computation of which comments are "new" since the user
/// last opened a post.
///
/// A comment is new iff: there is a prior-visit reference (`previousVisitAt`
/// non-nil — i.e. not the first-ever visit), it is a real comment (not a "load
/// more" placeholder), it was published strictly after `previousVisitAt`, and
/// it was not written by the current account. Comparison uses the comment's
/// `published` (creation) time, never `updated`, so edits don't re-flag.
public enum NewCommentState {
    public struct Result: Equatable, Sendable {
        /// `PostDetailCommentRow.id` (element id) of each new comment.
        public let newElementIds: Set<Int64>
        /// The new comment with the lowest display `position`, for
        /// "jump to first new". nil when there are none.
        public let firstNewElementId: Int64?

        public var count: Int {
            newElementIds.count
        }

        public init(newElementIds: Set<Int64>, firstNewElementId: Int64?) {
            self.newElementIds = newElementIds
            self.firstNewElementId = firstNewElementId
        }
    }

    public static func compute(
        orderedComments: [PostDetailCommentRow],
        previousVisitAt: Date?,
        currentAccountPersonId: Int64?
    ) -> Result {
        guard let previousVisitAt else {
            return Result(newElementIds: [], firstNewElementId: nil)
        }

        var newIds = Set<Int64>()
        var firstPosition: Int64?
        var firstId: Int64?

        for row in orderedComments {
            guard row.serverCommentId != nil, let published = row.published else {
                continue // "load more" placeholder
            }
            guard published > previousVisitAt else {
                continue
            }
            if let me = currentAccountPersonId, row.creatorPersonId == me {
                continue // the user's own comment
            }
            newIds.insert(row.id)
            if firstPosition == nil || row.position < firstPosition! {
                firstPosition = row.position
                firstId = row.id
            }
        }

        return Result(newElementIds: newIds, firstNewElementId: firstId)
    }
}
