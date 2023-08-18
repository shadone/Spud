//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import CoreData
import Foundation

@objc(LemmyPageElement)
public final class LemmyPageElement: NSManagedObject {
    @nonobjc
    public class func fetchRequest() -> NSFetchRequest<LemmyPageElement> {
        NSFetchRequest<LemmyPageElement>(entityName: "PageElement")
    }

    // MARK: Properties

    /// Index of the post inside this page.
    @NSManaged public var index: Int16

    // MARK: Relations

    @NSManaged public var post: LemmyPost

    // MARK: Reverse relationships

    @NSManaged public var page: LemmyPage
}
