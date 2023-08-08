//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import CoreData
import Foundation
import LemmyKit
import os.log

@objc(LemmyPostInfo) public final class LemmyPostInfo: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<LemmyPostInfo> {
        NSFetchRequest<LemmyPostInfo>(entityName: "PostInfo")
    }

    // MARK: Properties

    /// Link to the post in the original Lemmy instance.
    @NSManaged public var originalPostUrl: URL

    /// The title of the post.
    @NSManaged public var title: String
    /// The text body of the post.
    @NSManaged public var body: String?

    /// Thumbnail for the post.
    @NSManaged public var thumbnailUrl: URL?

    /// URL the post links to.
    @NSManaged public var url: URL?

    /// OEmbed title for the url.
    @NSManaged public var urlEmbedTitle: String?

    /// OEmbed description for the url.
    @NSManaged public var urlEmbedDescription: String?

    /// Number of comments.
    @NSManaged public var numberOfComments: Int64

    /// Overall score of the post.
    @NSManaged public var score: Int64
    /// Number of upvotes.
    @NSManaged public var numberOfUpvotes: Int64
    /// Number of downvotes.
    @NSManaged public var numberOfDownvotes: Int64
    /// See ``voteStatus``
    @NSManaged public var voteStatusRawValue: NSNumber?

    /// The timestamp when the post was published.
    @NSManaged public var published: Date

    // MARK: Meta properties

    /// Timestamp when this CoreData object was created.
    @NSManaged public var createdAt: Date

    /// Timestamp when this CoreData object was last updated.
    @NSManaged public var updatedAt: Date

    // MARK: Relations

    /// Post author.
    @NSManaged public var creator: LemmyPerson

    /// Community the post was published in.
    @NSManaged public var community: LemmyCommunity

    // MARK: Reverse relationships

    @NSManaged public var post: LemmyPost
}

extension LemmyPostInfo {
    convenience init(
        creator: LemmyPerson,
        community: LemmyCommunity,
        in context: NSManagedObjectContext
    ) {
        self.init(context: context)

        createdAt = Date()
        updatedAt = createdAt

        self.creator = creator
        self.community = community
    }
}
