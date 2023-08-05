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

/// Describes a Community on a given instances that is fetched with a given account.
///
/// This is a "header" used as a placeholder that views can watch for changes, the actual person data is
/// stored in ``LemmyCommunityInfo``.
@objc(LemmyCommunity) public final class LemmyCommunity: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<LemmyCommunity> {
        NSFetchRequest<LemmyCommunity>(entityName: "Community")
    }

    // MARK: Properties

    /// Community identifier. The identifier is local to this instance.
    @NSManaged public var communityId: CommunityId

    /// Timestamp when this CoreData object was created.
    @NSManaged public var createdAt: Date

    /// Timestamp when this CoreData object was last updated.
    @NSManaged public var updatedAt: Date

    // MARK: Relations

    /// The account which was used to fetch this community info.
    ///
    /// - Note: This is **not** the community home site.
    ///
    /// For example when fetching community info for `@memes@kbin.social` using an account logged in to `lemmy.world`,
    /// this account points to `lemmy.world`.
    @NSManaged public var account: LemmyAccount

    /// The extended info about the community.
    @NSManaged public var communityInfo: LemmyCommunityInfo?

    @NSManaged public var postInfos: Set<LemmyPostInfo>
}

extension LemmyCommunity {
    convenience init(communityId: CommunityId, in context: NSManagedObjectContext) {
        self.init(context: context)

        self.communityId = communityId

        self.createdAt = Date()
        self.updatedAt = createdAt
    }
}

extension LemmyCommunity {
    var identifierForLogging: String {
        "[\(communityId)]@\(account.site.identifierForLogging)"
    }
}
