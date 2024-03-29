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

@objc(LemmyPersonInfo)
public final class LemmyPersonInfo: NSManagedObject {
    @nonobjc
    public class func fetchRequest() -> NSFetchRequest<LemmyPersonInfo> {
        NSFetchRequest<LemmyPersonInfo>(entityName: "PersonInfo")
    }

    // MARK: Properties

    /// Username (aka nickname aka short users' name). e.g. "helloworld"
    @NSManaged public var name: String

    /// A display name for the user. e.g. "Hello World!"
    @NSManaged public var displayName: String?

    /// A URL for an avatar.
    @NSManaged public var avatarUrl: URL?

    /// The account creation date.
    @NSManaged public var personCreatedDate: Date

    /// The date person info was last updated by the person.
    @NSManaged public var personUpdatedDate: Date?

    /// The federated actor_id.
    /// e.g. `https://discuss.tchncs.de/u/milan`
    @NSManaged public var actorId: URL

    /// An optional bio, in markdown.
    @NSManaged public var bio: String?

    /// A URL for a banner.
    @NSManaged public var bannerUrl: URL?

    /// Whether the person is deleted.
    @NSManaged public var isDeletedPerson: Bool

    /// A matrix id, usually given an @person:matrix.org
    @NSManaged public var matrixUserId: String?

    /// Whether the person is local to this instance we fetch the info from.
    @NSManaged public var isLocal: Bool

    /// Whether the person is an admin.
    @NSManaged public var isAdmin: Bool

    /// Whether the person is a bot account.
    @NSManaged public var isBotAccount: Bool

    /// Whether the person is banned.
    @NSManaged public var isBanned: Bool

    /// When their ban, if it exists, expires, if at all.
    @NSManaged public var banExpires: Date?

    /// Number of posts made by the person.
    @NSManaged public var numberOfPosts: Int64

    /// Number of comments made by the person.
    @NSManaged public var numberOfComments: Int64

    // MARK: Meta properties

    /// Timestamp when this CoreData object was created.
    @NSManaged public var createdAt: Date

    /// Timestamp when this CoreData object was last updated.
    @NSManaged public var updatedAt: Date

    // MARK: Relations

    // MARK: Reverse relationships

    @NSManaged public var person: LemmyPerson
}

extension LemmyPersonInfo {
    convenience init(in context: NSManagedObjectContext) {
        self.init(context: context)
        createdAt = Date()
        updatedAt = createdAt
    }
}

public extension LemmyPersonInfo {
    /// Returns the home instance of the person.
    ///
    /// E.g. `https://lemmit.online/`
    var instanceActorId: InstanceActorId {
        // TODO: is this ok? should person's home site be determined Person.instance_id instead?
        InstanceActorId(from: actorId) ?? .invalid
    }

    /// See ``instanceActorId``
    var instanceActorIdPublisher: AnyPublisher<InstanceActorId, Never> {
        publisher(for: \.actorId)
            .map { InstanceActorId(from: $0) ?? .invalid }
            .eraseToAnyPublisher()
    }
}
