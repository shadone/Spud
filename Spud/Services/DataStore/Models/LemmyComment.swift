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

    /// The author of the comment.
    @NSManaged public var creatorName: String

    /// The content of the comment.
    @NSManaged public var body: String

    /// Overall score of the post.
    @NSManaged public var score: Int64
    /// Number of upvotes.
    @NSManaged public var numberOfUpvotes: Int64
    /// Number of downvotes.
    @NSManaged public var numberOfDownvotes: Int64

    /// The timestamp when the post was published.
    @NSManaged public var published: Date

    // MARK: Relations

    @NSManaged public var commentElements: Set<LemmyCommentElement>
    @NSManaged public var post: LemmyPost
}
