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
    public override var debugDescription: String {
        let objectIDUrl = site.objectID.uriRepresentation().absoluteString
        return "\(objectIDUrl)[\(site.normalizedInstanceUrl)]"
    }
}
