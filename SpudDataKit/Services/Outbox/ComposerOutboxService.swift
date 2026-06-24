//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

public struct ComposerOutboxFailure: Sendable, Equatable {
    public let clientToken: String
    public let kind: OutboundKind
}

public struct ComposerOutboxSuccess: Sendable, Equatable {
    public let clientToken: String
    public let kind: OutboundKind
    public let serverPostId: Int64?
}

public protocol ComposerOutboxServiceType: Actor {
    func submit(clientToken: String) async
    func retry(clientToken: String) async
    func discard(clientToken: String) async
    func drainOnce() async
    func drainAll() async
    func start() async
    var failureEvents: AsyncStream<ComposerOutboxFailure> { get }
    var successEvents: AsyncStream<ComposerOutboxSuccess> { get }
}

public actor ComposerOutboxService: ComposerOutboxServiceType {
    public static let maxAutoAttempts: Int64 = 8

    private let accountId: Int64
    private let appDatabase: AppDatabase
    private let performer: OutboundContentPerforming
    private let reachability: ReachabilityMonitoring
    private let now: @Sendable () -> Double

    private var failureContinuations: [UUID: AsyncStream<ComposerOutboxFailure>.Continuation] = [:]
    private var successContinuations: [UUID: AsyncStream<ComposerOutboxSuccess>.Continuation] = [:]
    private var started = false
    private var scheduledDrain: Task<Void, Never>?

    public init(
        accountId: Int64, appDatabase: AppDatabase, performer: OutboundContentPerforming,
        reachability: ReachabilityMonitoring, now: @escaping @Sendable () -> Double
    ) {
        self.accountId = accountId
        self.appDatabase = appDatabase
        self.performer = performer
        self.reachability = reachability
        self.now = now
    }

    public var failureEvents: AsyncStream<ComposerOutboxFailure> {
        AsyncStream { continuation in
            let id = UUID()
            failureContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in Task { await self?.removeFailure(id) } }
        }
    }

    public var successEvents: AsyncStream<ComposerOutboxSuccess> {
        AsyncStream { continuation in
            let id = UUID()
            successContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in Task { await self?.removeSuccess(id) } }
        }
    }

    private func removeFailure(_ id: UUID) {
        failureContinuations[id] = nil
    }

    private func removeSuccess(_ id: UUID) {
        successContinuations[id] = nil
    }

    private func emitFailure(_ f: ComposerOutboxFailure) {
        for c in failureContinuations.values {
            c.yield(f)
        }
    }

    private func emitSuccess(_ s: ComposerOutboxSuccess) {
        for c in successContinuations.values {
            c.yield(s)
        }
    }

    public func submit(clientToken: String) async {
        try? await appDatabase.markOutboundQueued(clientToken: clientToken, now: now())
        await drainOnce()
    }

    public func retry(clientToken: String) async {
        try? await appDatabase.markOutboundQueued(clientToken: clientToken, now: now())
        await drainOnce()
    }

    public func discard(clientToken: String) async {
        try? await appDatabase.deleteOutbound(clientToken: clientToken)
    }

    public func drainOnce() async {
        let due = await (try? appDatabase.dueOutbound(accountId: accountId, asOf: now())) ?? []
        await drain(records: due)
        await scheduleNextDrainIfNeeded()
    }

    public func drainAll() async {
        let all = await (try? appDatabase.dueOutbound(accountId: accountId, asOf: .greatestFiniteMagnitude)) ?? []
        await drain(records: all)
        await scheduleNextDrainIfNeeded()
    }

    public func start() async {
        guard !started else { return }
        started = true
        await drainAll()
        let stream = await MainActor.run { reachability.statusStream }
        Task { [weak self] in
            var wasOnline: Bool?
            for await online in stream {
                if online, wasOnline != true { await self?.drainAll() }
                wasOnline = online
            }
        }
    }

    private func drain(records: [OutboundContentRecord]) async {
        for record in records {
            guard let id = record.id else { continue }
            let token = record.clientToken
            let kind = OutboundKind(rawValue: record.kind) ?? .comment

            // Dedup: if a prior attempt actually committed (response lost), adopt + skip.
            if kind == .comment,
               await (try? appDatabase.matchingServerCommentExists(
                   accountId: accountId, postServerId: record.postServerId,
                   parentCommentServerId: record.parentCommentServerId, body: record.body
               )) == true
            {
                try? await appDatabase.deleteOutbound(clientToken: token)
                emitSuccess(ComposerOutboxSuccess(clientToken: token, kind: kind, serverPostId: nil))
                continue
            }

            try? await appDatabase.markOutboundSending(id: id, now: now())
            do {
                let serverPostId = try await performer.perform(record)
                try? await appDatabase.deleteOutbound(clientToken: token)
                emitSuccess(ComposerOutboxSuccess(clientToken: token, kind: kind, serverPostId: serverPostId))
            } catch {
                let online = await MainActor.run { reachability.isOnline }
                switch OutboxFailureClass.classify(error, isOnline: online) {
                case .transient:
                    let attempts = record.attempts + 1
                    if attempts >= Self.maxAutoAttempts {
                        try? await appDatabase.markOutboundFailed(id: id, lastError: String(describing: error), now: now())
                        emitFailure(ComposerOutboxFailure(clientToken: token, kind: kind))
                    } else {
                        let next = now() + Self.composerBackoffDelay(attempts: attempts)
                        try? await appDatabase.markOutboundRetrying(
                            id: id, lastError: String(describing: error), nextAttemptAt: next, now: now()
                        )
                    }
                case .permanent:
                    try? await appDatabase.markOutboundFailed(id: id, lastError: String(describing: error), now: now())
                    emitFailure(ComposerOutboxFailure(clientToken: token, kind: kind))
                }
            }
        }
    }

    /// Self-schedule a single drain at the earliest pending backoff time, so a
    /// transient failure recovers without waiting for a reachability flip or relaunch.
    private func scheduleNextDrainIfNeeded() async {
        scheduledDrain?.cancel()
        let pending = await (try? appDatabase.allOutbound(accountId: accountId)) ?? []
        let nowValue = now()
        let nextTimes = pending.compactMap { row -> Double? in
            guard row.status == OutboundStatus.queued.rawValue, let n = row.nextAttemptAt, n > nowValue else { return nil }
            return n
        }
        guard let earliest = nextTimes.min() else { return }
        let delay = max(0, earliest - nowValue)
        scheduledDrain = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) } catch { return }
            await self?.drainOnce()
        }
    }

    public static func composerBackoffDelay(attempts: Int64) -> Double {
        min(2.0 * pow(2.0, Double(max(0, attempts - 1))), 300)
    }
}
