//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import CoreData
import Foundation
import LemmyKit

@objc(LemmyFeed) public final class LemmyFeed: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<LemmyFeed> {
        NSFetchRequest<LemmyFeed>(entityName: "Feed")
    }

    // MARK: Properties

    /// Feed identifier. Random UUID.
    @NSManaged public var id: String

    /// Timestamp when this CoreData object was created.
    @NSManaged public var createdAt: Date

    // MARK: Frontpage

    /// See [sortType](x-source-tag://sortType)
    @NSManaged public var sortTypeRawValue: String?

    /// See [frontpageListingType](x-source-tag://frontpageListingType)
    @NSManaged public var frontpageListingTypeRawValue: String?

    // MARK: Relations

    @NSManaged public var pages: Set<LemmyPage>
    @NSManaged public var account: LemmyAccount

    // MARK: Functions

    public func addToPages(_ page: LemmyPage) {
        mutablePages.add(page)
    }

    // MARK: Private

    private var mutablePages: NSMutableSet {
        mutableSetValue(forKey: "pages")
    }
}

extension LemmyFeed {
    /// - Tag: sortType
    var sortType: SortType? {
        get {
            guard let rawValue = sortTypeRawValue else {
                return nil
            }

            guard let value = SortType(rawValue: rawValue) else {
                assertionFailure()
                return .active
            }

            return value
        }
        set {
            sortTypeRawValue = newValue?.rawValue
        }
    }

    /// - Tag: frontpageListingType
    var frontpageListingType: ListingType? {
        get {
            guard let rawValue = frontpageListingTypeRawValue else {
                return nil
            }

            guard let value = ListingType(rawValue: rawValue) else {
                assertionFailure()
                return .local
            }

            return value
        }
        set {
            frontpageListingTypeRawValue = newValue?.rawValue
        }
    }

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
        }

        self.account = account
    }

    /// Creates a new frontpage feed for a given category and sort order.
    convenience init(
        listingType: ListingType,
        sortType: SortType,
        in context: NSManagedObjectContext
    ) {
        self.init(entity: LemmyFeed.entity(), insertInto: context)

        id = UUID().uuidString
        createdAt = Date()

        frontpageListingType = listingType
        self.sortType = sortType
    }

    convenience init(
        duplicateOf originalFeed: LemmyFeed,
        sortType: SortType?,
        in context: NSManagedObjectContext
    ) {
        self.init(context: context)

        id = UUID().uuidString
        createdAt = Date()

        account = originalFeed.account

        frontpageListingTypeRawValue = originalFeed.frontpageListingTypeRawValue
        sortTypeRawValue = sortType?.rawValue ?? originalFeed.sortTypeRawValue
    }
}
