//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB

public struct NodeInfoRecord: Codable, Sendable, Equatable, Identifiable {
    public static let databaseTableName = "nodeInfo"

    public var id: Int64?
    public var instanceId: Int64
    public var softwareName: String
    public var softwareVersion: String
    public var isOpenRegistrationsAllowed: Bool
    public var numberOfLocalPosts: Int64
    public var numberOfLocalComments: Int64
    public var numberOfUsersTotal: Int64
    public var numberOfUsersHalfYear: Int64
    public var numberOfUsersMonth: Int64
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: Int64? = nil,
        instanceId: Int64,
        softwareName: String,
        softwareVersion: String,
        isOpenRegistrationsAllowed: Bool = false,
        numberOfLocalPosts: Int64 = 0,
        numberOfLocalComments: Int64 = 0,
        numberOfUsersTotal: Int64 = 0,
        numberOfUsersHalfYear: Int64 = 0,
        numberOfUsersMonth: Int64 = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.instanceId = instanceId
        self.softwareName = softwareName
        self.softwareVersion = softwareVersion
        self.isOpenRegistrationsAllowed = isOpenRegistrationsAllowed
        self.numberOfLocalPosts = numberOfLocalPosts
        self.numberOfLocalComments = numberOfLocalComments
        self.numberOfUsersTotal = numberOfUsersTotal
        self.numberOfUsersHalfYear = numberOfUsersHalfYear
        self.numberOfUsersMonth = numberOfUsersMonth
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension NodeInfoRecord: FetchableRecord, MutablePersistableRecord {
    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
