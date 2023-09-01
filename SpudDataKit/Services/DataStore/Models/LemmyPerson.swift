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
import SpudUtilKit

/// Describes a person, e.g. post or comment author.
///
/// This is a "header" used as a placeholder that views can watch for changes, the actual person data is
/// stored in ``LemmyPersonInfo``.
@objc(LemmyPerson)
public final class LemmyPerson: NSManagedObject {
    @nonobjc
    public class func fetchRequest() -> NSFetchRequest<LemmyPerson> {
        NSFetchRequest<LemmyPerson>(entityName: "Person")
    }

    /// Creates a request for fetching a Person by id at a given Instance.
    ///
    /// - Parameter personId: PersonId identifier local to the specified instance.
    /// - Parameter instance: Instance actorId. e.g. "https://lemmy.world", see ``InstanceActorId``.
    ///
    /// - Note: the instance specifies the Lemmy instance the personId is valid for. I.e. it is **not** the persons home site.
    @nonobjc
    public class func fetchRequest(
        personId: PersonId,
        instance: InstanceActorId
    ) -> NSFetchRequest<LemmyPerson> {
        let request = NSFetchRequest<LemmyPerson>(entityName: "Person")
        request.predicate = NSPredicate(
            format: "personId == %d && site.instance.actorIdRawValue == %@",
            personId, instance.actorId
        )
        return request
    }

    /// Creates a request for fetching a Person by id at a given instance (identified by site).
    ///
    /// - Parameter personId: PersonId identifier local to the specified instance.
    /// - Parameter site: Instance the `personId` is valid on, **not** the persons home site.
    @nonobjc
    public class func fetchRequest(
        personId: PersonId,
        site: LemmySite
    ) -> NSFetchRequest<LemmyPerson> {
        let request = NSFetchRequest<LemmyPerson>(entityName: "Person")
        request.predicate = NSPredicate(
            format: "personId == %d && site == %@",
            personId, site
        )
        return request
    }

    // MARK: Properties

    /// Person identifier. The identifier is local to this instance.
    @NSManaged public var personId: Int32

    /// Username (aka nickname aka short users' name). e.g. "helloworld"
    ///
    /// - Note: Intentionally optional. This is meant as a cached partial data.
    /// The source of truth is stored in ``personInfo`` when full person detail data is fetched.
    @NSManaged public var name: String?

    /// A display name for the user. e.g. "Hello World!"
    ///
    /// - Note: Intentionally optional. This is meant as a cached partial data.
    /// The source of truth is stored in ``personInfo`` when full person detail data is fetched.
    @NSManaged public var displayName: String?

    /// A URL for an avatar.
    ///
    /// - Note: Intentionally optional. This is meant as a cached partial data.
    /// The source of truth is stored in ``personInfo`` when full person detail data is fetched.
    @NSManaged public var avatarUrl: URL?

    // MARK: Meta properties

    /// Timestamp when this CoreData object was created.
    @NSManaged public var createdAt: Date

    /// Timestamp when this CoreData object was last updated.
    @NSManaged public var updatedAt: Date

    // MARK: Relations

    /// The site this person info was fetched via.
    ///
    /// - Note: This is **not** the persons home site.
    ///
    /// For example when fetching `@user@kbin.social` person info using an account logged in to `lemmy.world`,
    /// this site points to `lemmy.world`.
    ///
    /// - Note: This could've been a "LemmyAccount" but since Person objects don't have anything account specific
    /// we associate Person with a Site instead of making it per-account.
    @NSManaged public var site: LemmySite

    /// The extended info about the person.
    @NSManaged public var personInfo: LemmyPersonInfo?

    @NSManaged public var accountInfo: LemmyAccountInfo?

    // MARK: Reverse relationships

    @NSManaged public var postInfos: Set<LemmyPostInfo>
    @NSManaged public var comments: Set<LemmyComment>
}

extension LemmyPerson {
    convenience init(
        personId: Int32,
        site: LemmySite,
        in context: NSManagedObjectContext
    ) {
        self.init(context: context)

        self.personId = personId
        self.site = site

        createdAt = Date()
        updatedAt = createdAt
    }
}

extension LemmyPerson {
    var identifierForLogging: String {
        "[\(personId)]@\(site.identifierForLogging)"
    }
}
