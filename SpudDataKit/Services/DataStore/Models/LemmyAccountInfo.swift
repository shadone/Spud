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

@objc(LemmyAccountInfo) public final class LemmyAccountInfo: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<LemmyAccountInfo> {
        NSFetchRequest<LemmyAccountInfo>(entityName: "AccountInfo")
    }

    // MARK: Properties

    /// Internal Lemmy user identifier. The same identifier as in JWT sub claim.
    @NSManaged public var localAccountId: Int32

    /// User's email address.
    @NSManaged public var email: String?

    /// Whether to show NSFW content.
    @NSManaged public var showNsfw: Bool

    /// See ``defaultSortType``.
    @NSManaged public var defaultSortTypeRawValue: String

    /// See ``defaultListingType``.
    @NSManaged public var defaultListingTypeRawValue: String

    /// Whether to show avatars.
    @NSManaged public var showAvatars: Bool

    /// Whether to show comment / post scores.
    @NSManaged public var showScores: Bool

    /// Whether to show bot accounts.
    @NSManaged public var showBotAccounts: Bool

    /// Whether to show read posts.
    @NSManaged public var showReadPosts: Bool

    /// Whether their email has been verified.
    @NSManaged public var emailVerified: Bool

    /// Whether their registration application has been accepted.
    @NSManaged public var acceptedApplication: Bool

    /// A URL to add their 2-factor auth.
    @NSManaged public var totp2faUrl: URL?

    // MARK: Meta properties

    /// Timestamp when this CoreData object was created.
    @NSManaged public var createdAt: Date

    /// Timestamp when this CoreData object was last updated.
    @NSManaged public var updatedAt: Date

    // MARK: Relations

    @NSManaged public var account: LemmyAccount
    @NSManaged public var person: LemmyPerson
}

extension LemmyAccountInfo {
    convenience init(
        personId: Int32,
        in context: NSManagedObjectContext
    ) {
        self.init(context: context)

        person = LemmyPerson(personId: personId, in: context)
        person.accountInfo = self

        createdAt = Date()
        updatedAt = createdAt
    }
}

public extension LemmyAccountInfo {
    /// The default sort type for the user.
    var defaultSortType: SortType {
        get {
            guard let value = SortType(rawValue: defaultSortTypeRawValue) else {
                assertionFailure()
                return .active
            }

            return value
        }
        set {
            defaultSortTypeRawValue = newValue.rawValue
        }
    }

    /// The default listing type.
    var defaultListingType: ListingType {
        get {
            guard let value = ListingType(rawValue: defaultListingTypeRawValue) else {
                assertionFailure()
                return .subscribed
            }

            return value
        }
        set {
            defaultListingTypeRawValue = newValue.rawValue
        }
    }
}
