//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import OSLog

private let logger = Logger.appDatabase

public extension AppDatabase {
    /// Records that the post was opened. Resolves the account from
    /// `accountKeychainId`; no-ops (returns nil) if the account is unknown.
    /// Returns the `lastOpenedAt` value from *before* this open (nil on a
    /// first-ever open) for the new-comment delta.
    @discardableResult
    func recordPostOpened(
        accountKeychainId: String,
        serverPostId: Int64,
        commentCount: Int64?,
        snapshot: PostInteractionSnapshot?,
        now: Date = Date()
    ) async throws -> Date? {
        try await writer.write { db in
            guard let accountId = try Self.accountRowId(forKeychainId: accountKeychainId, in: db) else {
                return nil
            }
            let existing = try Self.interaction(accountId: accountId, postServerId: serverPostId, in: db)
            let (record, previous) = PostInteractionUpdate.applyingOpen(
                to: existing, accountId: accountId, postServerId: serverPostId,
                now: now, commentCount: commentCount, snapshot: snapshot
            )
            try Self.save(record, in: db)
            return previous
        }
    }

    /// Records that the post appeared on screen. Resolves the account from
    /// `accountKeychainId`; no-ops if the account is unknown.
    func recordPostSeen(
        accountKeychainId: String,
        serverPostId: Int64,
        snapshot: PostInteractionSnapshot,
        now: Date = Date()
    ) async throws {
        try await writer.write { db in
            guard let accountId = try Self.accountRowId(forKeychainId: accountKeychainId, in: db) else {
                return
            }
            let existing = try Self.interaction(accountId: accountId, postServerId: serverPostId, in: db)
            let record = PostInteractionUpdate.applyingSeen(
                to: existing, accountId: accountId, postServerId: serverPostId,
                now: now, snapshot: snapshot
            )
            try Self.save(record, in: db)
        }
    }

    /// Applies the retention policy. Saved posts are exempt. Returns the number
    /// of rows deleted.
    @discardableResult
    func prunePostInteractions(
        now: Date = Date(),
        seenRetention: TimeInterval = PostInteractionUpdate.defaultSeenRetention,
        openedRetention: TimeInterval = PostInteractionUpdate.defaultOpenedRetention
    ) async throws -> Int {
        try await writer.write { db in
            let records = try PostInteractionRecord.fetchAll(db)
            var deleted = 0
            for record in records {
                let isSaved = try Bool.fetchOne(
                    db,
                    sql: "SELECT isSaved FROM post WHERE accountId = ? AND postId = ?",
                    arguments: [record.accountId, record.postServerId]
                ) ?? false
                if PostInteractionUpdate.shouldPrune(
                    record, now: now, isSaved: isSaved,
                    seenRetention: seenRetention, openedRetention: openedRetention
                ) {
                    try record.delete(db)
                    deleted += 1
                }
            }
            return deleted
        }
    }

    // MARK: - Private helpers (run inside a database access closure)

    internal static func accountRowId(forKeychainId keychainId: String, in db: Database) throws -> Int64? {
        try AccountRecord
            .filter(Column("accountKeychainId") == keychainId)
            .fetchOne(db)?
            .id
    }

    internal static func interaction(accountId: Int64, postServerId: Int64, in db: Database) throws -> PostInteractionRecord? {
        try PostInteractionRecord
            .filter(Column("accountId") == accountId)
            .filter(Column("postServerId") == postServerId)
            .fetchOne(db)
    }

    internal static func save(_ record: PostInteractionRecord, in db: Database) throws {
        var record = record
        if record.id == nil {
            try record.insert(db)
        } else {
            try record.update(db)
        }
    }
}
