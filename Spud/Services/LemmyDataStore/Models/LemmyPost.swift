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

    @NSManaged public var communityName: String

    @NSManaged public var title: String

    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date

    // MARK: Relations

    @NSManaged public var pageElements: Set<LemmyPageElement>
}
