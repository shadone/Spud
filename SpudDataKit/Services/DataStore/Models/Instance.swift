//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import CoreData
import Foundation
import OSLog
import SpudUtilKit

private let logger = Logger.dataStore

@objc(Instance)
public final class Instance: NSManagedObject {
    @nonobjc
    public class func fetchRequest() -> NSFetchRequest<Instance> {
        NSFetchRequest<Instance>(entityName: "Instance")
    }

    // MARK: Properties

    /// The actor id that identifies the instance in the fediverse. Aka instance domain / hostname, aka "actor_id".
    ///
    /// e.g. "https://lemmy.world"
    ///
    /// - Note: This is intentionally stored as a string to ensure consistent normalization form so we can compare
    /// instances by comparing their actorId literally, without worrying about e.g. trailing slashes .
    @NSManaged public var actorIdRawValue: String

    // MARK: Meta properties

    /// Timestamp when this CoreData object was created.
    @NSManaged public var createdAt: Date

    // MARK: Relations

    @NSManaged public var nodeInfo: NodeInfo?
    @NSManaged public var site: LemmySite?

    // MARK: Reverse relationships
}

extension Instance {
    convenience init(
        actorId: InstanceActorId,
        in context: NSManagedObjectContext
    ) {
        self.init(entity: Instance.entity(), insertInto: context)

        self.actorId = actorId
        createdAt = Date()
    }
}

public extension Instance {
    var actorId: InstanceActorId {
        get {
            guard let actorId = InstanceActorId(from: actorIdRawValue) else {
                logger.assertionFailure("Failed to parse actorId '\(actorIdRawValue)'")
                return .invalid
            }
            return actorId
        }
        set {
            actorIdRawValue = newValue.actorId
        }
    }

    var actorIdPublisher: AnyPublisher<InstanceActorId, Never> {
        publisher(for: \.actorIdRawValue)
            .map { InstanceActorId(from: $0) ?? .invalid }
            .eraseToAnyPublisher()
    }
}

public extension Instance {
    var identifierForLogging: String {
        actorId.host
    }
}
