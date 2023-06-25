//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import CoreData
import Foundation
import os.log

@objc(LemmyAccount) public final class LemmyAccount: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<LemmyAccount> {
        NSFetchRequest<LemmyAccount>(entityName: "Account")
    }

    // MARK: Properties

    /// Unique identifier for an account, merely for internal use e.g. in logging.
    @NSManaged public var id: String

    @NSManaged public var isSignedOutAccountType: Bool

    /// Timestamp when this CoreData object was created.
    @NSManaged public var createdAt: Date

    /// Timestamp when this CoreData object was last updated.
    @NSManaged public var updatedAt: Date

    // MARK: Relations

    @NSManaged public var site: LemmySite
    @NSManaged public var feeds: Set<LemmyFeed>
    @NSManaged public var posts: Set<LemmyPost>
}

extension LemmyAccount {
    convenience init(
        signedOutAt site: LemmySite,
        in context: NSManagedObjectContext
    ) {
        self.init(entity: LemmyAccount.entity(), insertInto: context)

        self.id = "<anon>@\(site.instanceHostname)"
        self.site = site
        self.isSignedOutAccountType = true

        createdAt = Date()
        updatedAt = createdAt
    }
}

extension LemmyAccount {
    var identifierForLogging: String {
        id
    }
}
