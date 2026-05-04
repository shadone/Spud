//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB

public struct InstanceRecord: Codable, Sendable, Equatable, Identifiable {
    public static let databaseTableName = "instance"

    public var id: Int64?
    public var actorId: String
    public var createdAt: Date
    public var updatedAt: Date?

    public init(
        id: Int64? = nil,
        actorId: String,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.actorId = actorId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension InstanceRecord: FetchableRecord, MutablePersistableRecord {
    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public extension InstanceRecord {
    enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let actorId = Column(CodingKeys.actorId)
        public static let createdAt = Column(CodingKeys.createdAt)
        public static let updatedAt = Column(CodingKeys.updatedAt)
    }
}
