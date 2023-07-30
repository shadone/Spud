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

    /// Timestamp when this CoreData object was created.
    @NSManaged public var createdAt: Date

    // MARK: Relations

    @NSManaged public var instance: Instance

    @NSManaged public var accounts: Set<LemmyAccount>
    @NSManaged public var siteInfo: LemmySiteInfo?
    @NSManaged public var persons: Set<LemmyPerson>
}

extension LemmySite {
    convenience init(
        instance: Instance,
        in context: NSManagedObjectContext
    ) {
        self.init(entity: LemmySite.entity(), insertInto: context)

        self.instance = instance
        createdAt = Date()
    }
}

extension LemmySite {
    var instanceHostnamePublisher: AnyPublisher<String, Never> {
        instance.instanceHostnamePublisher
    }

        /// A helper for extracting the hostname part of the instance url
    var instanceHostname: String {
        instance.instanceHostname
    }

    var identifierForLogging: String {
        instance.identifierForLogging
    }
}
