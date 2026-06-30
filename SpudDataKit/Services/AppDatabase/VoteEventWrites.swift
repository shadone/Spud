//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB

public extension AppDatabase {
    // MARK: - Upsert

    /// Insert or update the vote-event row for `(accountId, entityType, entityServerId)`.
    ///
    /// On conflict the existing row is updated in-place (preserving its `id`) with
    /// the new `voteAction`, `votedAt`, and display-snapshot values.
    func upsertVoteEvent(
        accountId: Int64,
        entityType: String,
        entityServerId: Int64,
        voteAction: Int64,
        votedAt: Double,
        title: String?,
        body: String?,
        communityName: String?,
        communityActorId: String?,
        thumbnailUrl: String?,
        score: Int64?
    ) async throws {
        try await writer.write { db in
            if var existing = try VoteEventRecord
                .filter(Column("accountId") == accountId)
                .filter(Column("entityType") == entityType)
                .filter(Column("entityServerId") == entityServerId)
                .fetchOne(db)
            {
                existing.voteAction = voteAction
                existing.votedAt = votedAt
                existing.title = title
                existing.body = body
                existing.communityName = communityName
                existing.communityActorId = communityActorId
                existing.thumbnailUrl = thumbnailUrl
                existing.score = score
                try existing.update(db)
            } else {
                var record = VoteEventRecord(
                    accountId: accountId,
                    entityType: entityType,
                    entityServerId: entityServerId,
                    voteAction: voteAction,
                    votedAt: votedAt,
                    title: title,
                    body: body,
                    communityName: communityName,
                    communityActorId: communityActorId,
                    thumbnailUrl: thumbnailUrl,
                    score: score
                )
                try record.insert(db)
            }
        }
    }

    // MARK: - Delete

    /// Delete the vote-event row for `(accountId, entityType, entityServerId)`.
    ///
    /// No-op if no matching row exists. Used when the vote is removed (neutral) or
    /// when the outbox permanently rolls back a failed vote operation.
    func deleteVoteEvent(
        accountId: Int64,
        entityType: String,
        entityServerId: Int64
    ) async throws {
        try await writer.write { db in
            try VoteEventRecord
                .filter(Column("accountId") == accountId)
                .filter(Column("entityType") == entityType)
                .filter(Column("entityServerId") == entityServerId)
                .deleteAll(db)
        }
    }
}
