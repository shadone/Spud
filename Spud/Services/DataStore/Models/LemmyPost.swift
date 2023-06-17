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

    // MARK: Properties

    /// Post id.
    @NSManaged public var id: Int32

    @NSManaged public var creatorName: String
    @NSManaged public var communityName: String

    /// The title of the post.
    @NSManaged public var title: String
    /// The text body of the post.
    @NSManaged public var body: String?

    /// Number of comments.
    @NSManaged public var numberOfComments: Int64

    /// Overall score of the post.
    @NSManaged public var score: Int64
    /// Number of upvotes.
    @NSManaged public var numberOfUpvotes: Int64
    /// Number of downvotes.
    @NSManaged public var numberOfDownvotes: Int64

    /// The timestamp when the post was published.
    @NSManaged public var published: Date

    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date

    // MARK: Relations

    @NSManaged public var pageElements: Set<LemmyPageElement>
    @NSManaged public var account: LemmyAccount
}
