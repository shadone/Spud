//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import CoreData
import Foundation
import LemmyKit
import OSLog
import SpudUtilKit

private let logger = Logger(.dataStore)

@objc(LemmyFeed)
public final class LemmyFeed: NSManagedObject {
    @nonobjc
    public class func fetchRequest() -> NSFetchRequest<LemmyFeed> {
        NSFetchRequest<LemmyFeed>(entityName: "Feed")
    }

    // MARK: Properties

    /// Feed identifier.
    ///
    /// There is no special meaning to this identifier, it is only meant to uniquely identify this feed.
    @NSManaged public var id: String

    /// Used to identify where the feed was created from for debugging purposes.
    ///
    /// E.g. describes if the feed was made in a widget.
    @NSManaged public var identifierForDebugging: String?

    /// List of activity identifiers (see ``LemmyKit/Post/ap_id``) of posts that are already present in the feed.
    /// This is used to deduplicate the feed.
    @NSManaged public var postActivityIds: Set<URL>

    /// See ``sortType``.
    @NSManaged public var sortTypeRawValue: String

    // MARK: Frontpage

    /// See ``frontpageListingType``.
    @NSManaged public var frontpageListingTypeRawValue: String?

    // MARK: Community

    /// The name of the community this feed represents.
    @NSManaged public var communityName: String?

    /// See ``communityInstanceActorId``
    @NSManaged public var communityInstanceActorIdRawValue: String?

    // MARK: Meta properties

    /// Timestamp when this CoreData object was created.
    @NSManaged public var createdAt: Date

    // MARK: Relations

    @NSManaged public var pages: Set<LemmyPage>
    @NSManaged public var account: LemmyAccount

    // MARK: Reverse relationships

    // MARK: Functions

    public func addToPages(_ page: LemmyPage) {
        mutablePages.add(page)
    }

    // MARK: Private

    private var mutablePages: NSMutableSet {
        mutableSetValue(forKey: "pages")
    }
}

public extension LemmyFeed {
    /// Sort order for the feed. Applies to either ``frontpageListingType`` or ``communityName`` depending
    /// on which one is set.
    var sortType: Components.Schemas.SortType {
        get {
            guard let value = Components.Schemas.SortType(fromDataStore: sortTypeRawValue) else {
                logger.assertionFailure("Failed to parse sort type '\(sortTypeRawValue)'")
                return .Active
            }
            return value
        }
        set {
            sortTypeRawValue = newValue.dataStoreRawValue
        }
    }

    /// The type of frontpage listing for the feed.
    var frontpageListingType: Components.Schemas.ListingType? {
        get {
            guard let rawValue = frontpageListingTypeRawValue else {
                return nil
            }

            guard let value = Components.Schemas.ListingType(fromDataStore: rawValue) else {
                logger.assertionFailure("Failed to parse listing type '\(rawValue)'")
                return .Local
            }

            return value
        }
        set {
            frontpageListingTypeRawValue = newValue?.dataStoreRawValue
        }
    }

    /// The instance the ``communityName`` belongs to.
    var communityInstanceActorId: InstanceActorId? {
        get {
            guard let rawValue = communityInstanceActorIdRawValue else {
                return nil
            }

            guard let url = URL(string: rawValue) else {
                logger.assertionFailure("Failed to parse url '\(rawValue)'")
                return nil
            }

            guard let value = InstanceActorId(from: url) else {
                logger.assertionFailure("Faield to parse instance actor id '\(rawValue)'")
                return nil
            }

            return value
        }
        set {
            communityInstanceActorIdRawValue = newValue?.actorId
        }
    }
}

extension LemmyFeed {
    convenience init(
        _ feedType: FeedType,
        account: LemmyAccount,
        in context: NSManagedObjectContext
    ) {
        switch feedType {
        case let .frontpage(listingType, sortType):
            self.init(
                listingType: listingType,
                sortType: sortType,
                in: context
            )

        case let .community(communityName, instance, sortType):
            self.init(
                communityName: communityName,
                instanceActorId: instance,
                sortType: sortType,
                in: context
            )
        }

        postActivityIds = .init()

        self.account = account
    }

    /// Creates a new frontpage feed for a given category and sort order.
    convenience init(
        listingType: Components.Schemas.ListingType,
        sortType: Components.Schemas.SortType,
        in context: NSManagedObjectContext
    ) {
        self.init(entity: LemmyFeed.entity(), insertInto: context)

        id = UUID().uuidString
        createdAt = Date()

        postActivityIds = .init()

        frontpageListingType = listingType
        self.sortType = sortType
    }

    convenience init(
        communityName: String,
        instanceActorId: InstanceActorId,
        sortType: Components.Schemas.SortType,
        in context: NSManagedObjectContext
    ) {
        self.init(entity: LemmyFeed.entity(), insertInto: context)

        id = UUID().uuidString
        createdAt = Date()

        postActivityIds = .init()

        self.communityName = communityName
        communityInstanceActorId = instanceActorId
        self.sortType = sortType
    }

    convenience init(
        duplicateOf originalFeed: LemmyFeed,
        sortType: Components.Schemas.SortType?,
        in context: NSManagedObjectContext
    ) {
        self.init(context: context)

        id = UUID().uuidString
        createdAt = Date()

        postActivityIds = .init()

        account = originalFeed.account

        frontpageListingTypeRawValue = originalFeed.frontpageListingTypeRawValue
        sortTypeRawValue = sortType?.rawValue ?? originalFeed.sortTypeRawValue

        communityName = originalFeed.communityName
        communityInstanceActorIdRawValue = originalFeed.communityInstanceActorIdRawValue
    }
}
