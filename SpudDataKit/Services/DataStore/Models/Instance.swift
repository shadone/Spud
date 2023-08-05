//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import CoreData
import Foundation
import SpudUtilKit
import os.log

@objc(Instance) public final class Instance: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Instance> {
        NSFetchRequest<Instance>(entityName: "Instance")
    }

    // MARK: Properties

    /// The actor id that identifies the instance in the fediverse. Aka instance domain / hostname, aka "actor_id".
    ///
    /// e.g. "https://lemmy.world"
    ///
    /// - Note: This is intentionally stored as a string to ensure consistent normalization form so we can compare
    /// instances by comparing their actorId literally, without worrying about e.g. trailing slashes .
    @NSManaged public var actorId: String

    // MARK: Meta properties

    /// Timestamp when this CoreData object was created.
    @NSManaged public var createdAt: Date

    // MARK: Relations

    @NSManaged public var nodeInfo: NodeInfo?
    @NSManaged public var site: LemmySite?
}

extension Instance {
    convenience init(
        actorId: String,
        in context: NSManagedObjectContext
    ) {
        self.init(entity: Instance.entity(), insertInto: context)

        self.actorId = actorId
        createdAt = Date()
    }
}

public extension Instance {
    var instanceHostnamePublisher: AnyPublisher<String, Never> {
        publisher(for: \.actorId)
            .map { URL(string: $0)!.safeHost }
            .eraseToAnyPublisher()
    }

        /// A helper for extracting the hostname part of the instance url
    var instanceHostname: String {
        URL(string: actorId)!.safeHost
    }

    var identifierForLogging: String {
        instanceHostname
    }
}
