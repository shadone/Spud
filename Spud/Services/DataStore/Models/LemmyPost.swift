//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import CoreData
import Foundation
import os.log

@objc(LemmyPost) public final class LemmyPost: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<LemmyPost> {
        NSFetchRequest<LemmyPost>(entityName: "Post")
    }

    public typealias PostId = Int32

    // MARK: Properties

    /// Post identifier. The identifier is local to this instance.
    @NSManaged public var localPostId: PostId

    /// Link to the post in the original Lemmy instance.
    @NSManaged public var originalPostUrl: URL

    @NSManaged public var creatorName: String
    @NSManaged public var communityName: String

    /// The title of the post.
    @NSManaged public var title: String
    /// The text body of the post.
    @NSManaged public var body: String?

    /// Thumbnail for the post.
    @NSManaged public var thumbnailUrl: URL?

    /// URL the post links to.
    @NSManaged public var url: URL?

    /// Number of comments.
    @NSManaged public var numberOfComments: Int64

    /// Overall score of the post.
    @NSManaged public var score: Int64
    /// Number of upvotes.
    @NSManaged public var numberOfUpvotes: Int64
    /// Number of downvotes.
    @NSManaged public var numberOfDownvotes: Int64
    /// See [voteStatus](x-source-tag://voteStatus)
    @NSManaged public var voteStatusRawValue: NSNumber?

    /// The timestamp when the post was published.
    @NSManaged public var published: Date

    /// Timestamp when this CoreData object was created.
    @NSManaged public var createdAt: Date

    /// Timestamp when this CoreData object was last updated.
    @NSManaged public var updatedAt: Date

    // MARK: Relations

    @NSManaged public var pageElements: Set<LemmyPageElement>
    @NSManaged public var commentElements: Set<LemmyCommentElement>
    @NSManaged public var account: LemmyAccount
}
