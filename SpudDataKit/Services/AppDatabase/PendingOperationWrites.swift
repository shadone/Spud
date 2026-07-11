//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import LemmyKit

public extension AppDatabase {
    // MARK: - Enqueue

    func enqueueOutboxOperation(_ op: OutboxOperation, accountId: Int64, now: Double) async throws {
        try await writer.write { db in
            let existing = try Self.fetchPending(db, accountId: accountId, op: op)
            // Coalescing: preserve the original baseline from the first enqueue.
            // Only read the current DB state when there is no existing pending row.
            let baseline: Int64? = if let existing {
                existing.baseline
            } else {
                try Self.currentBaseline(db, accountId: accountId, op: op)
            }

            // Toggle-to-baseline: desired state matches the last-confirmed state —
            // revert the optimistic projection and remove the pending row.
            if Self.desiredEqualsBaseline(op.desiredState, baseline: baseline) {
                try Self.restoreBaseline(
                    db,
                    accountId: accountId,
                    entityType: op.entityType,
                    entityServerId: op.entityServerId,
                    kind: op.kind,
                    baseline: baseline
                )
                if let id = existing?.id {
                    try Self.deletePending(db, id: id)
                }
                return
            }

            // Forward optimistic apply.
            try Self.applyAbsolute(
                db,
                accountId: accountId,
                entityType: op.entityType,
                entityServerId: op.entityServerId,
                desired: op.desiredState
            )

            if var row = existing {
                row.desiredState = op.desiredState.encoded
                row.attempts = 0
                row.lastError = nil
                row.nextAttemptAt = now
                row.updatedAt = now
                try row.update(db)
            } else {
                var row = PendingOperationRecord(
                    accountId: accountId,
                    entityType: op.entityType.rawValue,
                    entityServerId: op.entityServerId,
                    kind: op.kind.rawValue,
                    desiredState: op.desiredState.encoded,
                    baseline: baseline,
                    attempts: 0,
                    lastError: nil,
                    nextAttemptAt: now,
                    createdAt: now,
                    updatedAt: now
                )
                try row.insert(db)
            }
        }
    }

    // MARK: - Queries

    func dueOutboxOperations(accountId: Int64, asOf now: Double) async throws -> [PendingOperationRecord] {
        try await writer.read { db in
            try PendingOperationRecord
                .filter(Column("accountId") == accountId)
                .filter(Column("nextAttemptAt") == nil || Column("nextAttemptAt") <= now)
                .order(Column("createdAt").asc)
                .fetchAll(db)
        }
    }

    func allOutboxOperations(accountId: Int64) async throws -> [PendingOperationRecord] {
        try await writer.read { db in
            try PendingOperationRecord
                .filter(Column("accountId") == accountId)
                .order(Column("createdAt").asc)
                .fetchAll(db)
        }
    }

    // MARK: - Mutations

    func removeOutboxOperation(id: Int64) async throws {
        try await writer.write { db in
            try Self.deletePending(db, id: id)
        }
    }

    func recordOutboxAttempt(id: Int64, lastError: String, nextAttemptAt: Double) async throws {
        try await writer.write { db in
            try db.execute(
                sql: """
                    UPDATE pendingOperation
                    SET attempts = attempts + 1, lastError = ?, nextAttemptAt = ?
                    WHERE id = ?
                    """,
                arguments: [lastError, nextAttemptAt, id]
            )
        }
    }

    func rollbackOutboxOperation(_ record: PendingOperationRecord) async throws {
        try await writer.write { db in
            guard let entityType = OutboxEntityType(rawValue: record.entityType),
                  let kind = OutboxKind(rawValue: record.kind)
            else { return }
            try Self.restoreBaseline(
                db,
                accountId: record.accountId,
                entityType: entityType,
                entityServerId: record.entityServerId,
                kind: kind,
                baseline: record.baseline
            )
            if let id = record.id {
                try Self.deletePending(db, id: id)
            }
        }
    }
}

// MARK: - Private helpers

private extension AppDatabase {
    /// Apply an absolute desired state to the local DB fields.
    /// Shared by forward-apply, toggle-to-baseline, and rollback.
    static func applyAbsolute(
        _ db: Database,
        accountId: Int64,
        entityType: OutboxEntityType,
        entityServerId: Int64,
        desired: OutboxDesiredState
    ) throws {
        switch desired {
        case let .vote(status):
            let currentDB = try currentVoteStatus(
                db,
                accountId: accountId,
                entityType: entityType,
                entityServerId: entityServerId
            )
            let delta = OutboxProjection.voteScoreDelta(currentDB: currentDB, desired: status)
            let dbVote = OutboxProjection.dbVoteStatus(for: status)
            if entityType == .post {
                try OptimisticWrites.setPostVote(
                    db,
                    accountId: accountId,
                    serverPostId: entityServerId,
                    voteStatus: dbVote,
                    scoreDelta: delta
                )
            } else {
                try OptimisticWrites.setCommentVote(
                    db,
                    accountId: accountId,
                    serverCommentId: entityServerId,
                    voteStatus: dbVote,
                    scoreDelta: delta
                )
            }

        case let .save(value):
            if entityType == .post {
                try OptimisticWrites.setPostSaved(
                    db,
                    accountId: accountId,
                    serverPostId: entityServerId,
                    isSaved: value
                )
            } else {
                try OptimisticWrites.setCommentSaved(
                    db,
                    accountId: accountId,
                    serverCommentId: entityServerId,
                    isSaved: value
                )
            }

        case let .hide(value):
            try OptimisticWrites.setPostHidden(
                db,
                accountId: accountId,
                serverPostId: entityServerId,
                isHidden: value
            )

        case let .delete(value):
            // Delete/restore of the user's own post or comment.
            if entityType == .post {
                try OptimisticWrites.setPostDeleted(
                    db,
                    accountId: accountId,
                    serverPostId: entityServerId,
                    isDeleted: value
                )
            } else {
                try OptimisticWrites.setCommentDeleted(
                    db,
                    accountId: accountId,
                    serverCommentId: entityServerId,
                    isDeleted: value
                )
            }

        case let .subscribe(value):
            // Forward optimistic apply: subscribing projects the honest "Pending"
            // state (the server may answer Subscribed or Pending; the performer's
            // authoritative mirror upgrades it), unsubscribing projects
            // NotSubscribed. `entityServerId` is the SERVER community id.
            try OptimisticWrites.setCommunitySubscribed(
                db,
                accountId: accountId,
                serverCommunityId: entityServerId,
                state: value ? .pending : .notSubscribed
            )
        }
    }

    /// Read the current local field value encoded as a baseline integer.
    /// Vote: 1/0/nil  Save/hide: 1/0
    static func currentBaseline(_ db: Database, accountId: Int64, op: OutboxOperation) throws -> Int64? {
        switch op.desiredState {
        case .vote:
            return try currentVoteStatus(
                db,
                accountId: accountId,
                entityType: op.entityType,
                entityServerId: op.entityServerId
            )
        case .save:
            let saved: Bool
            if op.entityType == .post {
                saved = try Bool.fetchOne(
                    db,
                    sql:
                    "SELECT isSaved FROM post WHERE postId = ? AND accountId = ?",
                    arguments: [op.entityServerId, accountId]
                ) ?? false
            } else {
                saved = try Bool.fetchOne(
                    db,
                    sql: """
                        SELECT isSaved FROM comment
                        WHERE localCommentId = ?
                          AND postId IN (SELECT id FROM post WHERE accountId = ?)
                        """,
                    arguments: [op.entityServerId, accountId]
                ) ?? false
            }
            return saved ? 1 : 0
        case .hide:
            let hidden = try Bool.fetchOne(
                db,
                sql:
                "SELECT isHidden FROM post WHERE postId = ? AND accountId = ?",
                arguments: [op.entityServerId, accountId]
            ) ?? false
            return hidden ? 1 : 0
        case .delete:
            let deleted: Bool
            if op.entityType == .post {
                deleted = try Bool.fetchOne(
                    db,
                    sql:
                    "SELECT isDeleted FROM post WHERE postId = ? AND accountId = ?",
                    arguments: [op.entityServerId, accountId]
                ) ?? false
            } else {
                deleted = try Bool.fetchOne(
                    db,
                    sql: """
                        SELECT isDeleted FROM comment
                        WHERE localCommentId = ?
                          AND postId IN (SELECT id FROM post WHERE accountId = ?)
                        """,
                    arguments: [op.entityServerId, accountId]
                ) ?? false
            }
            return deleted ? 1 : 0
        case .subscribe:
            // Capture the PRIOR CommunitySubscribedState so a rollback can
            // restore Pending / ApprovalRequired / Denied (not just on/off).
            // Encoded via CommunitySubscribedState.outboxBaseline: 0/1/2/3/4.
            let raw = try String.fetchOne(
                db,
                sql: "SELECT subscribedState FROM community WHERE communityId = ? AND accountId = ?",
                arguments: [op.entityServerId, accountId]
            )
            let state = raw.flatMap(CommunitySubscribedState.init(rawValue:)) ?? .notSubscribed
            return state.outboxBaseline
        }
    }

    /// Read the current voteStatus from the DB, scoped to the account.
    static func currentVoteStatus(
        _ db: Database,
        accountId: Int64,
        entityType: OutboxEntityType,
        entityServerId: Int64
    ) throws -> Int64? {
        if entityType == .post {
            return try Int64.fetchOne(
                db,
                sql:
                "SELECT voteStatus FROM post WHERE postId = ? AND accountId = ?",
                arguments: [entityServerId, accountId]
            )
        } else {
            return try Int64.fetchOne(
                db,
                sql: """
                    SELECT voteStatus FROM comment
                    WHERE localCommentId = ?
                      AND postId IN (SELECT id FROM post WHERE accountId = ?)
                    """,
                arguments: [entityServerId, accountId]
            )
        }
    }

    /// Returns true when the desired state matches the baseline (toggle-to-original).
    ///
    /// For subscribe this compares the desired Bool (1/0) against the baseline
    /// int: it matches only when the baseline is `notSubscribed` (0) or
    /// `subscribed` (1) — an in-flight baseline (`pending` 2, `approvalRequired`
    /// 3, `denied` 4) never equals either desired value, so a tap from any of
    /// those always creates a fresh op rather than coalescing away (correct: the
    /// user is changing a not-yet-confirmed / rejected request).
    static func desiredEqualsBaseline(_ desired: OutboxDesiredState, baseline: Int64?) -> Bool {
        switch desired {
        case let .vote(status): OutboxProjection.dbVoteStatus(for: status) == baseline
        case let .save(value), let .hide(value), let .delete(value), let .subscribe(value): (value ? 1 : 0) == baseline
        }
    }

    /// Restores the local projection to the stored `baseline` for the given kind.
    ///
    /// Most kinds decode the baseline into an ``OutboxDesiredState`` and re-apply
    /// it via ``applyAbsolute``. Subscribe is special: its baseline is a
    /// ``CommunitySubscribedState`` (0/1/2/3/4), which a 2-valued `.subscribe(Bool)`
    /// cannot represent, so it is restored directly — preserving a prior Pending /
    /// ApprovalRequired / Denied state that the forward apply would otherwise collapse.
    static func restoreBaseline(
        _ db: Database,
        accountId: Int64,
        entityType: OutboxEntityType,
        entityServerId: Int64,
        kind: OutboxKind,
        baseline: Int64?
    ) throws {
        if kind == .subscribe {
            try OptimisticWrites.setCommunitySubscribed(
                db,
                accountId: accountId,
                serverCommunityId: entityServerId,
                state: CommunitySubscribedState(outboxBaseline: baseline)
            )
        } else {
            let baselineState = decodeBaseline(baseline, kind: kind)
            try applyAbsolute(
                db,
                accountId: accountId,
                entityType: entityType,
                entityServerId: entityServerId,
                desired: baselineState
            )
        }
    }

    /// Decode a stored baseline integer back to an OutboxDesiredState for the given kind.
    ///
    /// Not called for `.subscribe` — its 3-valued baseline is restored directly
    /// by ``restoreBaseline`` (a Bool `.subscribe` case would lose Pending). The
    /// case below exists only to keep the switch exhaustive.
    static func decodeBaseline(_ baseline: Int64?, kind: OutboxKind) -> OutboxDesiredState {
        switch kind {
        case .vote:
            let status: LikeStatus
            switch baseline {
            case 1: status = .liked
            case 0: status = .disliked
            default: status = .neutral
            }
            return .vote(status)
        case .save:
            return .save(baseline == 1)
        case .hide:
            return .hide(baseline == 1)
        case .delete:
            return .delete(baseline == 1)
        case .subscribe:
            return .subscribe(baseline == 1)
        }
    }

    static func fetchPending(_ db: Database, accountId: Int64, op: OutboxOperation) throws -> PendingOperationRecord? {
        try PendingOperationRecord
            .filter(Column("accountId") == accountId)
            .filter(Column("entityType") == op.entityType.rawValue)
            .filter(Column("entityServerId") == op.entityServerId)
            .filter(Column("kind") == op.kind.rawValue)
            .fetchOne(db)
    }

    static func deletePending(_ db: Database, id: Int64) throws {
        _ = try PendingOperationRecord.deleteOne(db, key: id)
    }
}

// MARK: - Reconciliation guard helper

extension AppDatabase {
    /// Returns the set of pending outbox operation kinds for a given entity,
    /// used by importers to avoid clobbering un-synced optimistic state.
    static func pendingOutboxKinds(
        _ db: Database,
        accountId: Int64,
        entityType: String,
        entityServerId: Int64
    ) throws -> Set<OutboxKind> {
        let raws = try String.fetchAll(
            db,
            sql: """
                SELECT kind FROM pendingOperation
                WHERE accountId = ? AND entityType = ? AND entityServerId = ?
                """,
            arguments: [accountId, entityType, entityServerId]
        )
        return Set(raws.compactMap(OutboxKind.init(rawValue:)))
    }

    /// Returns the community ROW ids (for `accountId`) that have an in-flight
    /// `.subscribe` op. Joins `pendingOperation.entityServerId` (the SERVER
    /// community id the outbox stores) to `community.communityId`, scoped to the
    /// account. Used by `setFollowedCommunities` to exempt these communities from
    /// the server's junction rewrite so an optimistic subscribe/unsubscribe stands
    /// until the outbox confirms it.
    static func pendingSubscribeCommunityRowIds(
        _ db: Database,
        accountId: Int64
    ) throws -> Set<Int64> {
        let ids = try Int64.fetchAll(
            db,
            sql: """
                SELECT c.id FROM community c
                JOIN pendingOperation p
                  ON p.entityServerId = c.communityId AND p.accountId = c.accountId
                WHERE c.accountId = ?
                  AND p.entityType = ?
                  AND p.kind = ?
                """,
            arguments: [accountId, OutboxEntityType.community.rawValue, OutboxKind.subscribe.rawValue]
        )
        return Set(ids)
    }

    /// Of the given community ROW ids, returns the subset that currently have an
    /// `accountFollowedCommunity` junction row for `accountId`. Snapshots the
    /// pre-rewrite optimistic membership so `setFollowedCommunities` can restore it.
    static func followedCommunityRowIds(
        _ db: Database,
        accountId: Int64,
        among communityRowIds: Set<Int64>
    ) throws -> Set<Int64> {
        guard !communityRowIds.isEmpty else { return [] }
        let placeholders = databaseQuestionMarks(count: communityRowIds.count)
        let ids = try Int64.fetchAll(
            db,
            sql: """
                SELECT communityId FROM accountFollowedCommunity
                WHERE accountId = ? AND communityId IN (\(placeholders))
                """,
            arguments: StatementArguments([accountId] + communityRowIds.map { $0 })
        )
        return Set(ids)
    }

    /// True when a content-outbox row is editing this post and has not yet synced
    /// (its status is `sending` or `failed`). Used by `upsertPost`'s reconcile
    /// guard to preserve the locally-applied title/body/url/nsfw against a
    /// concurrent feed/`getPost` refresh until the edit reaches the server.
    ///
    /// `draft` and `queued` rows are intentionally excluded: a draft hasn't been
    /// submitted yet (no optimistic write applied), and a queued row is about to
    /// be picked up by the drain whose successful `editPost` upsert bypasses the
    /// guard anyway. Sending/failed are the windows where the optimistic write is
    /// live but the server hasn't confirmed it.
    static func hasPendingOutboundPostEdit(
        _ db: Database,
        accountId: Int64,
        serverPostId: Int64
    ) throws -> Bool {
        try Bool.fetchOne(
            db,
            sql: """
                SELECT 1 FROM outboundContent
                WHERE accountId = ?
                  AND editPostServerId = ?
                  AND status IN (?, ?)
                LIMIT 1
                """,
            arguments: [
                accountId, serverPostId,
                OutboundStatus.sending.rawValue, OutboundStatus.failed.rawValue,
            ]
        ) ?? false
    }
}
