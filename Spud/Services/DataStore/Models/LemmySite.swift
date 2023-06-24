//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import CoreData
import Foundation
import os.log

@objc(LemmySite) public final class LemmySite: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<LemmySite> {
        NSFetchRequest<LemmySite>(entityName: "Site")
    }

    // MARK: Properties

    /// Identifies on which Lemmy instance this account is used on.
    /// aka "actor_id".
    /// e.g. "https://lemmy.world"
    @NSManaged public var instanceUrl: URL

    /// Timestamp when this CoreData object was created.
    @NSManaged public var createdAt: Date

    // MARK: Relations

    @NSManaged public var accounts: Set<LemmyAccount>
    @NSManaged public var siteInfo: LemmySiteInfo
}
