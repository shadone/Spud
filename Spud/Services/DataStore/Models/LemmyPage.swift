//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import CoreData
import Foundation

@objc(LemmyPage) public final class LemmyPage: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<LemmyPage> {
        NSFetchRequest<LemmyPage>(entityName: "Page")
    }

    // MARK: Properties

    /// Timestamp when the page was fetched.
    @NSManaged public var createdAt: Date
    /// Page number.
    @NSManaged public var index: Int16

    // MARK: Relations

    @NSManaged public var pageElements: Set<LemmyPageElement>
    @NSManaged public var feed: LemmyFeed?
}
