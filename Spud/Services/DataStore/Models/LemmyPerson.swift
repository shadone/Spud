//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import CoreData
import Foundation
import os.log

@objc(LemmyPerson) public final class LemmyPerson: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<LemmyPerson> {
        NSFetchRequest<LemmyPerson>(entityName: "Person")
    }

    // MARK: Properties

    /// Person identifier. The identifier is local to this instance.
    @NSManaged public var personId: Int32

    /// Timestamp when this CoreData object was created.
    @NSManaged public var createdAt: Date

    /// Timestamp when this CoreData object was last updated.
    @NSManaged public var updatedAt: Date

    // MARK: Relations

    /// The site this person info was fetched via.
    ///
    /// - Note: This is **not** the persons home site.
    ///
    /// For example when fetching `@user@kbin.social` person info using an account logged in to `lemmy.world`,
    /// this site points to `lemmy.world`.
    @NSManaged public var site: LemmySite

    @NSManaged public var accountInfo: LemmyAccountInfo?
    @NSManaged public var personInfo: LemmyPersonInfo?
    @NSManaged public var posts: Set<LemmyPost>
    @NSManaged public var comments: Set<LemmyComment>
}

extension LemmyPerson {
    convenience init(personId: Int32, in context: NSManagedObjectContext) {
        self.init(context: context)

        self.personId = personId

        self.createdAt = Date()
        self.updatedAt = createdAt
    }
}

extension LemmyPerson {
    var identifierForLogging: String {
        "[\(personId)]@\(site.identifierForLogging)"
    }
}
