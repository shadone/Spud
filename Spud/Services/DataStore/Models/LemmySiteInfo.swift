//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import CoreData
import Foundation
import LemmyKit
import os.log

@objc(LemmySiteInfo) public final class LemmySiteInfo: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<LemmySiteInfo> {
        NSFetchRequest<LemmySiteInfo>(entityName: "SiteInfo")
    }

    // MARK: Properties

    /// Short name for the instance. E.g. "tchncs"
    @NSManaged public var name: String
    @NSManaged public var sidebar: String?
    /// Lemmy instance version. E.g. "0.18.0"
    @NSManaged public var version: String

    @NSManaged public var bannerUrl: URL?
    @NSManaged public var iconUrl: URL?

    /// See ``defaultPostListingType``.
    @NSManaged public var defaultPostListingTypeRawValue: String
    @NSManaged public var descriptionText: String?
    @NSManaged public var enableDownvotes: Bool
    @NSManaged public var enableNsfw: Bool
    @NSManaged public var legalInformation: String?

    @NSManaged public var numberOfComments: Int64
    @NSManaged public var numberOfCommunities: Int64
    @NSManaged public var numberOfPosts: Int64
    @NSManaged public var numberOfUsers: Int64
    @NSManaged public var numberOfUsersDay: Int64
    @NSManaged public var numberOfUsersWeek: Int64
    @NSManaged public var numberOfUsersMonth: Int64
    @NSManaged public var numberOfUsersHalfYear: Int64

    @NSManaged public var publicKey: String

    /// The date this sites' info was published by the site admins.
    @NSManaged public var infoPublishedDate: Date
    /// The date this sites' info was last updated by the site admins.
    @NSManaged public var infoUpdatedDate: Date?

    /// Timestamp when this CoreData object was created.
    @NSManaged public var createdAt: Date

    /// Timestamp when this CoreData object was last updated.
    @NSManaged public var updatedAt: Date

    // MARK: Relations

    @NSManaged public var site: LemmySite
}

extension LemmySiteInfo {
    /// Which listing type should be opened by default.
    var defaultPostListingType: ListingType {
        get {
            guard let value = ListingType(rawValue: defaultPostListingTypeRawValue) else {
                assertionFailure()
                return .all
            }

            return value
        }
        set {
            defaultPostListingTypeRawValue = newValue.rawValue
        }
    }
}
