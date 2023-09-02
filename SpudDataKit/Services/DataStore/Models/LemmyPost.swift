//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import CoreData
import Foundation
import LemmyKit
import OSLog

@objc(LemmyPost)
public final class LemmyPost: NSManagedObject {
    @nonobjc
    public class func fetchRequest() -> NSFetchRequest<LemmyPost> {
        NSFetchRequest<LemmyPost>(entityName: "Post")
    }

    @nonobjc
    public class func fetchRequest(
        postId: PostId,
        account: LemmyAccount
    ) -> NSFetchRequest<LemmyPost> {
        let request = NSFetchRequest<LemmyPost>(entityName: "Post")
        request.predicate = NSPredicate(
            format: "postId == %d && account == %@",
            postId, account
        )
        return request
    }

    // MARK: Properties

    /// Post identifier. The identifier is local to this instance.
    @NSManaged public var postId: PostId

    // MARK: Meta properties

    /// Timestamp when this CoreData object was created.
    @NSManaged public var createdAt: Date

    /// Timestamp when this CoreData object was last updated.
    @NSManaged public var updatedAt: Date

    // MARK: Relations

    /// The account this post was fetched with.
    @NSManaged public var account: LemmyAccount

    /// Additional info about the post.
    @NSManaged public var postInfo: LemmyPostInfo?

    // MARK: Reverse relationships

    @NSManaged public var pageElements: Set<LemmyPageElement>
    @NSManaged public var commentElements: Set<LemmyCommentElement>
}

extension LemmyPost {
    convenience init(
        postId: PostId,
        account: LemmyAccount,
        in context: NSManagedObjectContext
    ) {
        self.init(context: context)

        self.postId = postId

        createdAt = Date()
        updatedAt = createdAt

        self.account = account
    }
}

extension LemmyPost {
    var identifierForLogging: String {
        "[\(postId)]@\(account.site.identifierForLogging)"
    }
}
