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

    /// Normalized Lemmy instance url.
    ///
    /// Identifies on which Lemmy instance this account is used on.
    /// aka "actor_id".
    /// e.g. "https://lemmy.world"
    ///
    /// Stored as ``URL.normalizedInstanceUrlString``
    ///
    /// - Note: this is intentionally stored as a string to ensure consistent normalization form.
    @NSManaged public var normalizedInstanceUrl: String

    /// Timestamp when this CoreData object was created.
    @NSManaged public var createdAt: Date

    // MARK: Relations

    @NSManaged public var accounts: Set<LemmyAccount>
    @NSManaged public var siteInfo: LemmySiteInfo?
}

extension LemmySite {
    convenience init(
        normalizedInstanceUrl: String,
        in context: NSManagedObjectContext
    ) {
        self.init(entity: LemmySite.entity(), insertInto: context)

        self.normalizedInstanceUrl = normalizedInstanceUrl
        createdAt = Date()
    }
}

extension LemmySite {
    /// A helper for extracting the hostname part of the instance url
    var instanceHostname: String {
        let url = URL(string: normalizedInstanceUrl)!

        let host: String?
        if #available(iOS 16.0, *) {
            host = url.host(percentEncoded: false)
        } else {
            host = url.host
        }

        guard let host else {
            assertionFailure("Failed to get hostname from url '\(normalizedInstanceUrl)'")
            return url.absoluteString
        }

        return host
    }

    var identifierForLogging: String {
        instanceHostname
    }
}
