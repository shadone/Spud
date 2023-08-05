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

@objc(LemmyPersonInfo) public final class LemmyPersonInfo: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<LemmyPersonInfo> {
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
    @NSManaged public var accountCreationDate: Date

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

    /// Total upvote score for all posts for the person.
    @NSManaged public var totalScoreForPosts: Int64

    /// Number of comments made by the person.
    @NSManaged public var numberOfComments: Int64

    /// Total upvote score for all comments for the person.
    @NSManaged public var totalScoreForComments: Int64

    /// Timestamp when this CoreData object was created.
    @NSManaged public var createdAt: Date

    /// Timestamp when this CoreData object was last updated.
    @NSManaged public var updatedAt: Date

    // MARK: Relations

    @NSManaged public var person: LemmyPerson
}

extension LemmyPersonInfo {
    convenience init(in context: NSManagedObjectContext) {
        self.init(context: context)
        createdAt = Date()
        updatedAt = createdAt
    }
}

extension LemmyPersonInfo {
    /// Returns the home instance of the person.
    var hostnameFromActorId: String {
        // TODO: is this ok? should person's home site be determined Person.instance_id instead?

        // TODO: shall we care about a port number?

        actorId.safeHost
    }

    var hostnameFromActorIdPublisher: AnyPublisher<String, Never> {
        publisher(for: \.actorId)
            .map { $0.safeHost }
            .eraseToAnyPublisher()
    }
}
