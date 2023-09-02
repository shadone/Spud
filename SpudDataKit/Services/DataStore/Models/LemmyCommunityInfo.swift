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

@objc(LemmyCommunityInfo)
public final class LemmyCommunityInfo: NSManagedObject {
    @nonobjc
    public class func fetchRequest() -> NSFetchRequest<LemmyCommunityInfo> {
        NSFetchRequest<LemmyCommunityInfo>(entityName: "CommunityInfo")
    }

    // MARK: Properties

    /// The unique name of the community. E.g. `mylittlepony`
    @NSManaged public var name: String

    /// A longer title, that can contain other characters, and doesn't have to be unique.
    @NSManaged public var title: String

    /// A sidebar / markdown description.
    @NSManaged public var descriptionText: String?

    /// Whether the community is removed by a mod.
    @NSManaged public var isRemoved: Bool

    /// The date community was created.
    @NSManaged public var communityCreatedDate: Date

    /// The date community info was last updated.
    @NSManaged public var communityUpdatedDate: Date?

    /// Whether its an NSFW community.
    @NSManaged public var isNsfw: Bool

    /// The federated actor_id.
    ///
    /// E.g. `https://lemmit.online/c/mylittlepony`
    @NSManaged public var actorId: URL

    /// Whether the community is local.
    @NSManaged public var isLocal: Bool

    /// A URL for an icon.
    @NSManaged public var icon: URL?

    /// A URL for a banner.
    @NSManaged public var banner: URL?

    /// Whether the community is hidden.
    @NSManaged public var isHidden: Bool

    /// Whether posting is restricted to mods only.
    @NSManaged public var isPostingRestrictedToMods: Bool

    // MARK: Meta properties

    /// Timestamp when this CoreData object was created.
    @NSManaged public var createdAt: Date

    /// Timestamp when this CoreData object was last updated.
    @NSManaged public var updatedAt: Date

    // MARK: Relations

    @NSManaged public var community: LemmyCommunity
}

extension LemmyCommunityInfo {
    convenience init(in context: NSManagedObjectContext) {
        self.init(context: context)
        createdAt = Date()
        updatedAt = createdAt
    }
}

public extension LemmyCommunityInfo {
    /// Returns the home instance of the community.
    var hostnameFromActorId: String {
        // TODO: is this ok? should community's home site be determined Community.instance_id instead?

        // TODO: shall we care about a port number?

        actorId.safeHost
    }

    var hostnameFromActorIdPublisher: AnyPublisher<String, Never> {
        publisher(for: \.actorId)
            .map(\.safeHost)
            .eraseToAnyPublisher()
    }
}
