//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import CoreData
import Foundation
import LemmyKit

@objc(LemmyComment) public final class LemmyComment: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<LemmyComment> {
        NSFetchRequest<LemmyComment>(entityName: "Comment")
    }

    // MARK: Properties

    /// Comment identifier. The identifier is local to this instance.
    @NSManaged public var localCommentId: Int32

    /// Link to the comment in the original Lemmy instance.
    @NSManaged public var originalCommentUrl: URL

    /// The content of the comment.
    @NSManaged public var body: String

    /// Overall score of the post.
    @NSManaged public var score: Int64
    /// Number of upvotes.
    @NSManaged public var numberOfUpvotes: Int64
    /// Number of downvotes.
    @NSManaged public var numberOfDownvotes: Int64
    /// See ``voteStatus``.
    @NSManaged public var voteStatusRawValue: NSNumber?

    /// The timestamp when the post was published.
    @NSManaged public var published: Date

    // MARK: Meta properties

    /// Timestamp when this CoreData object was created.
    @NSManaged public var createdAt: Date

    /// Timestamp when this CoreData object was last updated.
    @NSManaged public var updatedAt: Date

    // MARK: Relations

    @NSManaged public var post: LemmyPost

    /// The author of the comment.
    @NSManaged public var creator: LemmyPerson

    // MARK: Reverse relationships

    @NSManaged public var commentElements: Set<LemmyCommentElement>
}

extension LemmyComment {
    var identifierForLogging: String {
        "[\(localCommentId)]@\(post.account.site.identifierForLogging)"
    }
}
