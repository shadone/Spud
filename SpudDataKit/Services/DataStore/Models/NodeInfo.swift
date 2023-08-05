//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import CoreData
import Foundation
import SemVer
import os.log

@objc(NodeInfo) public final class NodeInfo: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<NodeInfo> {
        NSFetchRequest<NodeInfo>(entityName: "NodeInfo")
    }

    // MARK: Properties

    /// See ``softwareName``.
    @NSManaged public var softwareNameRawValue: String

    /// See ``softwareVersion``.
    @NSManaged public var softwareVersionRawValue: String

    /// The amount of posts that were made by users that are registered on this server.
    @NSManaged public var numberOfLocalPosts: Int64

    /// The amount of comments that were made by users that are registered on this server.
    @NSManaged public var numberOfLocalComments: Int64

    /// The amount of users that signed in at least once in the last 30 days.
    @NSManaged public var numberOfUsersMonth: Int64

    /// The amount of users that signed in at least once in the last 180 days.
    @NSManaged public var numberOfUsersHalfYear: Int64

    /// The total amount of on this server registered users.
    @NSManaged public var numberOfUsersTotal: Int64

    /// Whether this server allows open self-registration.
    @NSManaged public var isOpenRegistrationsAllowed: Bool

    // MARK: Meta properties

    /// Timestamp when this CoreData object was created.
    @NSManaged public var createdAt: Date

    /// Timestamp when this CoreData object was last updated.
    @NSManaged public var updatedAt: Date

    // MARK: Relations

    @NSManaged public var instance: Instance
}

extension NodeInfo {
    /// The canonical name of this server software.
    var softwareName: NodeInfoSoftware {
        get {
            guard let software = NodeInfoSoftware(rawValue: softwareNameRawValue) else {
                assertionFailure("Got unknown NodeInfoSoftware: '\(softwareNameRawValue)'")
                return .lemmy
            }
            return software
        }
        set {
            softwareNameRawValue = newValue.rawValue
        }
    }

    /// The version of the software the instance runs on.
    var softwareVersion: Version {
        get {
            guard let version = Version(softwareVersionRawValue) else {
                assertionFailure("Got software version that cannot be parsed as semver: '\(softwareVersionRawValue)'")
                return .init(major: 0)
            }
            return version
        }
        set {
            softwareVersionRawValue = newValue.versionString()
        }
    }
}

extension NodeInfo {
    convenience init(
        in context: NSManagedObjectContext
    ) {
        self.init(entity: Instance.entity(), insertInto: context)

        createdAt = Date()
    }
}
