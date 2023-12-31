//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import CoreData
import Foundation

@objc(LemmyPage)
public final class LemmyPage: NSManagedObject {
    @nonobjc
    public class func fetchRequest() -> NSFetchRequest<LemmyPage> {
        NSFetchRequest<LemmyPage>(entityName: "Page")
    }

    // MARK: Properties

    /// Page number.
    @NSManaged public var index: Int16

    // MARK: Meta properties

    /// Timestamp when this CoreData object was created.
    @NSManaged public var createdAt: Date

    // MARK: Relations

    @NSManaged public var pageElements: Set<LemmyPageElement>

    // MARK: Reverse relationships

    @NSManaged public var feed: LemmyFeed?
}
