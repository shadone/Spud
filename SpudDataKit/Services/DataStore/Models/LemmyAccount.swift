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

    /// Unique identifier for an account, merely for internal use e.g. in logging or storing credentials in keychain.
    @NSManaged public var id: String

    /// Returns true if the account is created automatically by the app for internal purposes e.g. fetching
    /// Lemmy site info for an instance user does not have an account for.
    /// Service account implies "signed out" account type.
    @NSManaged public var isServiceAccount: Bool

    /// Returns true if the account is for logged out anonymous browsing. Typically only read-only Lemmy
    /// operations are possible.
    @NSManaged public var isSignedOutAccountType: Bool

    /// Specifies if the account is marked as "default" i.e. account that is used by default on app launch.
    /// Only one account at a time can be default.
    @NSManaged public var isDefaultAccount: Bool

    // MARK: Meta properties

    /// Timestamp when this CoreData object was created.
    @NSManaged public var createdAt: Date

    /// Timestamp when this CoreData object was last updated.
    @NSManaged public var updatedAt: Date

    // MARK: Relations

    @NSManaged public var site: LemmySite

    // MARK: Reverse relationships

    @NSManaged public var accountInfo: LemmyAccountInfo?
    @NSManaged public var feeds: Set<LemmyFeed>
    @NSManaged public var posts: Set<LemmyPost>
    @NSManaged public var communities: Set<LemmyCommunity>
}

extension LemmyAccount {
    convenience init(
        signedOutAt site: LemmySite,
        in context: NSManagedObjectContext
    ) {
        self.init(entity: LemmyAccount.entity(), insertInto: context)

        self.id = "<anon>@\(site.instanceHostname)"
        self.site = site
        self.isSignedOutAccountType = true
        self.isServiceAccount = false
        self.isDefaultAccount = false

        createdAt = Date()
        updatedAt = createdAt
    }

    convenience init(
        userId: String,
        at site: LemmySite,
        in context: NSManagedObjectContext
    ) {
        self.init(entity: LemmyAccount.entity(), insertInto: context)

        self.id = "\(userId)@\(site.instanceHostname)"
        self.site = site
        self.isSignedOutAccountType = false
        self.isServiceAccount = false
        self.isDefaultAccount = false

        createdAt = Date()
        updatedAt = createdAt
    }
}

extension LemmyAccount {
    var identifierForLogging: String {
        id
    }
}
