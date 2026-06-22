//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB

/// A persisted, not-yet-synced idempotent set-state mutation (vote/save/hide).
/// Coalesced per `(accountId, entityType, entityServerId, kind)` by a unique key.
public struct PendingOperationRecord: Codable, FetchableRecord, MutablePersistableRecord, Sendable, Equatable {
    public var id: Int64?
    public var accountId: Int64
    public var entityType: String
    public var entityServerId: Int64
    public var kind: String
    public var desiredState: Int64
    /// Prior local state to roll back to: vote `voteStatus` (1/0/nil) or save/hide bool (1/0).
    public var baseline: Int64?
    public var attempts: Int64
    public var lastError: String?
    public var nextAttemptAt: Double?
    public var createdAt: Double
    public var updatedAt: Double

    public static let databaseTableName = "pendingOperation"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
