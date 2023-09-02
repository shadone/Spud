//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import CoreData
import Foundation
import LemmyKit

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

    // MARK: Frontpage

    /// See ``sortType``.
    @NSManaged public var sortTypeRawValue: String

    /// See ``frontpageListingType``.
    @NSManaged public var frontpageListingTypeRawValue: String?

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
    /// Sort order for the feed.
    var sortType: SortType {
        get {
            guard let value = SortType(rawValue: sortTypeRawValue) else {
                assertionFailure()
                return .active
            }

            return value
        }
        set {
            sortTypeRawValue = newValue.rawValue
        }
    }

    /// The type of frontpage listing for the feed.
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
        }

        postActivityIds = .init()

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

        postActivityIds = .init()

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

        postActivityIds = .init()

        account = originalFeed.account

        frontpageListingTypeRawValue = originalFeed.frontpageListingTypeRawValue
        sortTypeRawValue = sortType?.rawValue ?? originalFeed.sortTypeRawValue
    }
}
