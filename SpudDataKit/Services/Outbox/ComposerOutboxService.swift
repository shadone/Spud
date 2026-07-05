//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

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

    /// Structured diagnostic recorder. Best-effort: failures must never propagate to drain callers.
    private let diagnostics: DiagnosticLogging

    /// Lemmy instance HOST (e.g. `lemmy.world`) for diagnostic event tagging.
    /// Pass `InstanceActorId.hostWithPort` — NOT a full URL.
    private let instance: String?

    private var failureContinuations: [UUID: AsyncStream<ComposerOutboxFailure>.Continuation] = [:]
    private var successContinuations: [UUID: AsyncStream<ComposerOutboxSuccess>.Continuation] = [:]
    private var started = false
    private var scheduledDrain: Task<Void, Never>?

    /// Tokens currently being sent by an in-progress `drain`. Because `dueOutbound`
    /// also returns `sending` rows and `perform` suspends on the network, a
    /// concurrent drain (background kick + scheduled retry + reachability flip)
    /// could re-select an in-flight row and send the same non-idempotent content
    /// twice. This actor-isolated reservation set is checked-and-inserted
    /// synchronously per record so a concurrent drain observes the reservation.
    private var inFlight: Set<String> = []

    public init(
        accountId: Int64, appDatabase: AppDatabase, performer: OutboundContentPerforming,
        reachability: ReachabilityMonitoring, now: @escaping @Sendable () -> Double,
        diagnostics: DiagnosticLogging, instance: String?
    ) {
        self.accountId = accountId
        self.appDatabase = appDatabase
        self.performer = performer
        self.reachability = reachability
        self.now = now
        self.diagnostics = diagnostics
        self.instance = instance
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
        await emitEnqueue(clientToken: clientToken)
        drainInBackground()
    }

    public func retry(clientToken: String) async {
        try? await appDatabase.markOutboundQueued(clientToken: clientToken, now: now())
        await emitEnqueue(clientToken: clientToken)
        drainInBackground()
    }

    /// Emits `op.enqueue` for the just-queued token. Performs a best-effort
    /// DB read to extract the content kind and target server id for the metadata.
    private func emitEnqueue(clientToken: String) async {
        let rows = await (try? appDatabase.allOutbound(accountId: accountId)) ?? []
        let row = rows.first { $0.clientToken == clientToken }
        var metadata: [String: String] = [:]
        if let row, let kind = OutboundKind(rawValue: row.kind) {
            metadata["kind"] = String(describing: kind)
            if let targetId = row.postServerId ?? row.communityServerId {
                metadata["targetServerId"] = String(targetId)
            }
        }
        await diagnostics.record(
            category: .composerOutbox,
            level: .info,
            event: "op.enqueue",
            message: "content enqueued",
            instance: instance,
            metadata: metadata.isEmpty ? nil : metadata
        )
    }

    /// Kicks a drain on a detached background task so callers (`submit` / `retry`)
    /// return immediately after the fast DB write, without blocking on the network
    /// round-trip. This is what makes the optimistic UI appear instantly.
    private func drainInBackground() {
        Task { [weak self] in await self?.drainOnce() }
    }

    public func discard(clientToken: String) async {
        try? await appDatabase.deleteOutbound(clientToken: clientToken)
    }

    public func drainOnce() async {
        let due = await (try? appDatabase.dueOutbound(accountId: accountId, asOf: now())) ?? []
        await diagnostics.record(
            category: .composerOutbox,
            level: .info,
            event: "drain.start",
            message: "drain started",
            instance: instance,
            metadata: ["trigger": "enqueue", "dueCount": String(due.count)]
        )
        await drain(records: due)
        await scheduleNextDrainIfNeeded()
    }

    public func drainAll() async {
        let all = await (try? appDatabase.dueOutbound(accountId: accountId, asOf: .greatestFiniteMagnitude)) ?? []
        await diagnostics.record(
            category: .composerOutbox,
            level: .info,
            event: "drain.start",
            message: "drain started",
            instance: instance,
            metadata: ["trigger": "reachability", "dueCount": String(all.count)]
        )
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
        var succeeded = 0
        var parked = 0
        var retried = 0

        for record in records {
            guard let id = record.id else { continue }
            let token = record.clientToken

            // In-flight guard: reserve this token synchronously (no await between
            // the contains-check and the insert) so a concurrent drain that
            // re-selects the same `sending` row skips it instead of re-sending
            // non-idempotent content. Released on every exit path via `defer`.
            if inFlight.contains(token) {
                await diagnostics.record(
                    category: .composerOutbox,
                    level: .debug,
                    event: "inflight.skip",
                    message: "skipping in-flight token",
                    instance: instance,
                    metadata: nil
                )
                continue
            }
            inFlight.insert(token)
            defer { inFlight.remove(token) }

            let kind = OutboundKind(rawValue: record.kind) ?? .comment

            // Dedup: if a prior attempt actually committed (response lost), adopt + skip.
            // This block is comment-create only (`kind == .comment`); new-post and
            // all edits never enter it. Skipped for comment edits
            // (`editCommentServerId != nil`): an edit targets an existing comment by
            // design, so a matching server comment is expected and must not
            // short-circuit the send (`editComment` is idempotent — a lost-response
            // retry simply re-applies the same content).
            if kind == .comment,
               record.editCommentServerId == nil,
               await (try? appDatabase.matchingServerCommentExists(
                   accountId: accountId, postServerId: record.postServerId,
                   parentCommentServerId: record.parentCommentServerId, body: record.body
               )) == true
            {
                try? await appDatabase.deleteOutbound(clientToken: token)
                emitSuccess(ComposerOutboxSuccess(clientToken: token, kind: kind, serverPostId: nil))
                await diagnostics.record(
                    category: .composerOutbox,
                    level: .notice,
                    event: "dedup.adopt",
                    message: "adopted existing server comment, skipping send",
                    instance: instance,
                    metadata: ["kind": String(describing: kind)]
                )
                succeeded += 1
                continue
            }

            await diagnostics.record(
                category: .composerOutbox,
                level: .debug,
                event: "op.attempt",
                message: "attempting send",
                instance: instance,
                metadata: ["kind": String(describing: kind), "attempts": String(record.attempts)]
            )
            try? await appDatabase.markOutboundSending(id: id, now: now())
            do {
                let serverPostId = try await performer.perform(record)
                try? await appDatabase.deleteOutbound(clientToken: token)
                emitSuccess(ComposerOutboxSuccess(clientToken: token, kind: kind, serverPostId: serverPostId))
                await diagnostics.record(
                    category: .composerOutbox,
                    level: .info,
                    event: "op.success",
                    message: "send succeeded",
                    instance: instance,
                    metadata: ["kind": String(describing: kind)]
                )
                succeeded += 1
            } catch {
                let online = await MainActor.run { reachability.isOnline }
                switch OutboxFailureClass.classify(error, isOnline: online) {
                case .transient:
                    let attempts = record.attempts + 1
                    if attempts >= Self.maxAutoAttempts {
                        try? await appDatabase.markOutboundFailed(id: id, lastError: String(describing: error), now: now())
                        emitFailure(ComposerOutboxFailure(clientToken: token, kind: kind))
                        var metadata: [String: String] = [
                            "kind": String(describing: kind),
                            "error": String(describing: error),
                            "attempts": String(attempts),
                        ]
                        if case let .unknownServerError(httpStatus, _) = error as? LemmyApiError {
                            metadata["httpStatus"] = String(httpStatus)
                        } else if case let .apiError(.unknownServerError(httpStatus, _)) = error as? LemmyServiceError {
                            metadata["httpStatus"] = String(httpStatus)
                        }
                        await diagnostics.record(
                            category: .composerOutbox,
                            level: .error,
                            event: "op.permanentPark",
                            message: "max attempts exhausted, parked as failed",
                            instance: instance,
                            metadata: metadata
                        )
                        parked += 1
                    } else {
                        let next = now() + OutboxBackoff.delay(attempts: attempts)
                        try? await appDatabase.markOutboundRetrying(
                            id: id, lastError: String(describing: error), nextAttemptAt: next, now: now()
                        )
                        await diagnostics.record(
                            category: .composerOutbox,
                            level: .notice,
                            event: "op.transientRetry",
                            message: "transient failure, will retry",
                            instance: instance,
                            metadata: [
                                "kind": String(describing: kind),
                                "error": String(describing: error),
                                "attempts": String(attempts),
                                "nextAttemptAt": String(next),
                            ]
                        )
                        retried += 1
                    }
                case .permanent:
                    try? await appDatabase.markOutboundFailed(id: id, lastError: String(describing: error), now: now())
                    emitFailure(ComposerOutboxFailure(clientToken: token, kind: kind))
                    var metadata: [String: String] = [
                        "kind": String(describing: kind),
                        "error": String(describing: error),
                    ]
                    if case let .unknownServerError(httpStatus, _) = error as? LemmyApiError {
                        metadata["httpStatus"] = String(httpStatus)
                    } else if case let .apiError(.unknownServerError(httpStatus, _)) = error as? LemmyServiceError {
                        metadata["httpStatus"] = String(httpStatus)
                    }
                    await diagnostics.record(
                        category: .composerOutbox,
                        level: .error,
                        event: "op.permanentPark",
                        message: "permanent failure, parked as failed",
                        instance: instance,
                        metadata: metadata
                    )
                    parked += 1
                }
            }
        }

        await diagnostics.record(
            category: .composerOutbox,
            level: .info,
            event: "drain.finish",
            message: "drain finished",
            instance: instance,
            metadata: [
                "succeeded": String(succeeded),
                "parked": String(parked),
                "retried": String(retried),
            ]
        )
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
}
