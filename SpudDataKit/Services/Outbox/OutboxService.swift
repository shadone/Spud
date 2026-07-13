//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

/// Why an outbox operation permanently failed, when the UI needs to react
/// differently. `.notFound` means the target post no longer exists on the
/// server (`couldnt_find_post`); everything else is `.other`.
public enum OutboxFailureReason: Sendable, Equatable {
    case notFound
    case other
}

public struct OutboxFailure: Sendable, Equatable {
    public let entityType: OutboxEntityType
    public let entityServerId: Int64
    public let kind: OutboxKind
    public let reason: OutboxFailureReason
    /// True when the permanent failure was a genuine expired/revoked session
    /// (not a WAF 403). Drives MainWindow's "Session expired" re-login toast.
    public let isAuthExpiry: Bool
}

public protocol OutboxServiceType: Actor {
    func enqueue(_ op: OutboxOperation) async
    func drainOnce() async
    func drainAll() async
    func start() async
    var failureEvents: AsyncStream<OutboxFailure> { get }
}

public actor OutboxService: OutboxServiceType {
    private let accountId: Int64
    private let appDatabase: AppDatabase
    private let performer: OutboxNetworkPerforming
    private let reachability: ReachabilityMonitoring
    private let now: @Sendable () -> Double
    private var failureContinuations: [UUID: AsyncStream<OutboxFailure>.Continuation] = [:]
    private var started = false

    /// Durable diagnostic recorder. Best-effort: failures in `record` must never
    /// propagate to the drain loop.
    private let diagnostics: DiagnosticLogging

    /// The Lemmy instance host (e.g. `"lemmy.world"`) this outbox belongs to.
    /// Attached to every diagnostic event so log viewers can filter per-instance.
    /// `nil` when the account's instance could not be resolved at construction time.
    private let instance: String?

    public init(
        accountId: Int64,
        appDatabase: AppDatabase,
        performer: OutboxNetworkPerforming,
        reachability: ReachabilityMonitoring,
        now: @escaping @Sendable () -> Double,
        diagnostics: DiagnosticLogging,
        instance: String?
    ) {
        self.accountId = accountId
        self.appDatabase = appDatabase
        self.performer = performer
        self.reachability = reachability
        self.now = now
        self.diagnostics = diagnostics
        self.instance = instance
    }

    /// Actor-isolated computed property: registers the continuation synchronously
    /// before returning, so `let s = await service.failureEvents` then `enqueue` cannot race.
    public var failureEvents: AsyncStream<OutboxFailure> {
        AsyncStream { continuation in
            let id = UUID()
            failureContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeFailureContinuation(id) }
            }
        }
    }

    private func removeFailureContinuation(_ id: UUID) {
        failureContinuations[id] = nil
    }

    private func emitFailure(_ failure: OutboxFailure) {
        for continuation in failureContinuations.values {
            continuation.yield(failure)
        }
    }

    public func enqueue(_ op: OutboxOperation) async {
        do {
            try await appDatabase.enqueueOutboxOperation(op, accountId: accountId, now: now())
        } catch {
            return
        }
        await diagnostics.record(
            category: .outbox,
            level: .info,
            event: "op.enqueue",
            message: "Enqueued outbox operation",
            instance: instance,
            metadata: [
                "entityType": op.entityType.rawValue,
                "entityServerId": String(op.entityServerId),
                "kind": op.kind.rawValue,
            ]
        )
        await drainOnce()
    }

    public func drainOnce() async {
        let due: [PendingOperationRecord]
        do {
            due = try await appDatabase.dueOutboxOperations(accountId: accountId, asOf: now())
        } catch {
            return
        }
        await diagnostics.record(
            category: .outbox,
            level: .info,
            event: "drain.start",
            message: "Starting drain pass (trigger: enqueue)",
            instance: instance,
            metadata: [
                "trigger": "enqueue",
                "dueCount": String(due.count),
            ]
        )
        await drain(records: due)
    }

    public func drainAll() async {
        let all: [PendingOperationRecord]
        do {
            all = try await appDatabase.dueOutboxOperations(accountId: accountId, asOf: .greatestFiniteMagnitude)
        } catch {
            return
        }
        await diagnostics.record(
            category: .outbox,
            level: .info,
            event: "drain.start",
            message: "Starting drain pass (trigger: reachability)",
            instance: instance,
            metadata: [
                "trigger": "reachability",
                "dueCount": String(all.count),
            ]
        )
        await drain(records: all)
    }

    public func start() async {
        guard !started else { return }
        started = true
        let stream = await MainActor.run { reachability.statusStream }
        Task { [weak self] in
            var wasOnline: Bool?
            for await online in stream {
                if online, wasOnline != true {
                    await self?.drainAll()
                }
                wasOnline = online
            }
        }
    }

    private func drain(records: [PendingOperationRecord]) async {
        var succeeded = 0
        var retried = 0
        var rolledBack = 0

        for record in records {
            guard let op = Self.operation(from: record), let id = record.id else { continue }
            await diagnostics.record(
                category: .outbox,
                level: .debug,
                event: "op.attempt",
                message: "Attempting outbox operation",
                instance: instance,
                metadata: [
                    "entityType": op.entityType.rawValue,
                    "entityServerId": String(op.entityServerId),
                    "attempts": String(record.attempts + 1),
                ]
            )
            do {
                try await performer.perform(op)
                try? await appDatabase.removeOutboxOperation(id: id)
                succeeded += 1
                await diagnostics.record(
                    category: .outbox,
                    level: .info,
                    event: "op.success",
                    message: "Outbox operation succeeded",
                    instance: instance,
                    metadata: [
                        "entityType": op.entityType.rawValue,
                        "entityServerId": String(op.entityServerId),
                    ]
                )
            } catch {
                let online = await MainActor.run { reachability.isOnline }
                switch OutboxFailureClass.classify(error, isOnline: online) {
                case .transient:
                    let next = now() + OutboxBackoff.delay(attempts: record.attempts + 1)
                    try? await appDatabase.recordOutboxAttempt(
                        id: id,
                        lastError: String(describing: error),
                        nextAttemptAt: next
                    )
                    retried += 1
                    await diagnostics.record(
                        category: .outbox,
                        level: .notice,
                        event: "op.transientRetry",
                        message: "Outbox operation will be retried (transient failure)",
                        instance: instance,
                        metadata: [
                            "entityType": op.entityType.rawValue,
                            "entityServerId": String(op.entityServerId),
                            "error": String(describing: error),
                            "attempts": String(record.attempts + 1),
                            "nextAttemptAt": String(next),
                        ]
                    )
                case .permanent:
                    // Emit diagnostic BEFORE rollback so the event exists even if
                    // emitFailure triggers additional processing on the caller side.
                    var metadata: [String: String] = [
                        "entityType": op.entityType.rawValue,
                        "entityServerId": String(op.entityServerId),
                        "error": String(describing: error),
                    ]
                    // Extract HTTP status when the error is an unknownServerError so
                    // the log viewer can filter by status without parsing the error string.
                    if case let .unknownServerError(httpStatus, _) = error as? LemmyApiError {
                        metadata["httpStatus"] = String(httpStatus)
                    } else if case let .apiError(.unknownServerError(httpStatus, _)) = error as? LemmyServiceError {
                        metadata["httpStatus"] = String(httpStatus)
                    }
                    await diagnostics.record(
                        category: .outbox,
                        level: .error,
                        event: "op.permanentRollback",
                        message: "Outbox operation permanently failed and was rolled back",
                        instance: instance,
                        metadata: metadata
                    )
                    // Flag the account for re-login when this permanent failure is
                    // a genuine auth-expiry. AuthExpiry excludes a bare 403, so a
                    // WAF-blocked write never trips it.
                    let isAuthExpiry = AuthExpiry.isAuthExpiry(error)
                    if isAuthExpiry {
                        try? await appDatabase.setAccountSessionNeedsReauth(accountId: accountId, true)
                    }
                    try? await appDatabase.rollbackOutboxOperation(record)
                    // A permanently-rolled-back vote removes its activity log entry.
                    if op.kind == .vote {
                        try? await appDatabase.deleteVoteEvent(
                            accountId: accountId,
                            entityType: op.entityType.rawValue,
                            entityServerId: op.entityServerId
                        )
                    }
                    // A not-found rejection means the post is gone server-side.
                    // Tombstone the stale cache so the feed badge + detail
                    // placeholder reflect reality, and tag the failure so the
                    // toast can be specific.
                    let reason: OutboxFailureReason
                    if op.entityType == .post, ContentNotFound.matchesPost(error) {
                        try? await appDatabase.markPostUnavailable(
                            accountId: accountId,
                            serverPostId: op.entityServerId
                        )
                        reason = .notFound
                    } else {
                        reason = .other
                    }
                    rolledBack += 1
                    emitFailure(OutboxFailure(
                        entityType: op.entityType,
                        entityServerId: op.entityServerId,
                        kind: op.kind,
                        reason: reason,
                        isAuthExpiry: isAuthExpiry
                    ))
                }
            }
        }

        await diagnostics.record(
            category: .outbox,
            level: .info,
            event: "drain.finish",
            message: "Drain pass complete",
            instance: instance,
            metadata: [
                "succeeded": String(succeeded),
                "retried": String(retried),
                "rolledBack": String(rolledBack),
            ]
        )
    }

    private static func operation(from record: PendingOperationRecord) -> OutboxOperation? {
        guard let entityType = OutboxEntityType(rawValue: record.entityType),
              let kind = OutboxKind(rawValue: record.kind) else { return nil }
        return OutboxOperation(
            entityType: entityType,
            entityServerId: record.entityServerId,
            desiredState: OutboxDesiredState.decode(kind: kind, raw: record.desiredState)
        )
    }
}
