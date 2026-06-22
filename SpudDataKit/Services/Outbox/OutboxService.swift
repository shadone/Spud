//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

public struct OutboxFailure: Sendable, Equatable {
    public let entityType: OutboxEntityType
    public let entityServerId: Int64
    public let kind: OutboxKind
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

    public init(
        accountId: Int64,
        appDatabase: AppDatabase,
        performer: OutboxNetworkPerforming,
        reachability: ReachabilityMonitoring,
        now: @escaping @Sendable () -> Double
    ) {
        self.accountId = accountId
        self.appDatabase = appDatabase
        self.performer = performer
        self.reachability = reachability
        self.now = now
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
        await drainOnce()
    }

    public func drainOnce() async {
        let due: [PendingOperationRecord]
        do {
            due = try await appDatabase.dueOutboxOperations(accountId: accountId, asOf: now())
        } catch {
            return
        }
        await drain(records: due)
    }

    public func drainAll() async {
        let all: [PendingOperationRecord]
        do {
            all = try await appDatabase.dueOutboxOperations(accountId: accountId, asOf: .greatestFiniteMagnitude)
        } catch {
            return
        }
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
        for record in records {
            guard let op = Self.operation(from: record), let id = record.id else { continue }
            do {
                try await performer.perform(op)
                try? await appDatabase.removeOutboxOperation(id: id)
            } catch {
                let online = await MainActor.run { reachability.isOnline }
                switch OutboxFailureClass.classify(error, isOnline: online) {
                case .transient:
                    let next = now() + backoffDelay(attempts: record.attempts + 1)
                    try? await appDatabase.recordOutboxAttempt(
                        id: id,
                        lastError: String(describing: error),
                        nextAttemptAt: next
                    )
                case .permanent:
                    try? await appDatabase.rollbackOutboxOperation(record)
                    emitFailure(OutboxFailure(
                        entityType: op.entityType,
                        entityServerId: op.entityServerId,
                        kind: op.kind
                    ))
                }
            }
        }
    }

    func backoffDelay(attempts: Int64) -> Double {
        min(2.0 * pow(2.0, Double(max(0, attempts - 1))), 300)
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
