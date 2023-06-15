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

    /// Identifies on which Lemmy instance this account is used on.
    /// e.g. "https://lemmy.world"
    @NSManaged public var instanceUrl: URL

    @NSManaged public var isSignedOutAccountType: Bool

    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date

    // MARK: Relations

    @NSManaged public var feeds: Set<LemmyFeed>
    @NSManaged public var posts: Set<LemmyPost>
}
