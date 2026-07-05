//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import OSLog
import SpudUtilKit

private let logger = Logger.schedulerService

@MainActor
public protocol SchedulerServiceType {
    func startService()
}

@MainActor
public protocol HasSchedulerService {
    var schedulerService: SchedulerServiceType { get }
}

@MainActor
public class SchedulerService: SchedulerServiceType {
    // MARK: Private

    private let appDatabase: AppDatabase
    private let accountService: AccountServiceType
    private let alertService: AlertServiceType
    private let diagnostics: DiagnosticLogging

    /// Per-account exponential back-off state. Prevents hammering an instance
    /// that is returning 403s or other persistent errors on every 5-minute tick.
    private var backoff = SchedulerBackoff()

    /// Clock injection for testability. Production uses `Date.init` (real wall time);
    /// tests supply a closure they control to step time without sleeping.
    private let now: @Sendable () -> Date

    /// Network reachability. Used to clear back-off and fire an immediate tick
    /// when connectivity is restored, so previously-failing accounts retry
    /// promptly rather than waiting up to 2 hours for the next scheduled window.
    private let reachabilityMonitor: ReachabilityMonitoring

    private var timer: Timer?

    /// Holds the Task that subscribes to `reachabilityMonitor.statusStream`.
    /// Retains the subscription for the lifetime of the service.
    private var reachabilityTask: Task<Void, Never>?

    // MARK: Functions

    public init(
        appDatabase: AppDatabase,
        accountService: AccountServiceType,
        alertService: AlertServiceType,
        diagnostics: DiagnosticLogging,
        now: @escaping @Sendable () -> Date = Date.init,
        reachabilityMonitor: ReachabilityMonitoring
    ) {
        self.appDatabase = appDatabase
        self.accountService = accountService
        self.alertService = alertService
        self.diagnostics = diagnostics
        self.now = now
        self.reachabilityMonitor = reachabilityMonitor
    }

    public func startService() {
        let fiveMinutes: TimeInterval = 300
        timer = Timer.scheduledTimer(withTimeInterval: fiveMinutes, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                // Periodically check if there is anything new needs to be fetched.
                await self.tick()
            }
        }

        // Trigger an extra check soon after app launch.
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.timer?.fire()
        }

        // On reconnect, clear all per-account back-off so previously-failing
        // accounts retry immediately instead of waiting out their back-off window
        // (up to 2 h). Mirrors the OutboxService.start() reachability pattern.
        let stream = reachabilityMonitor.statusStream
        reachabilityTask?.cancel()
        reachabilityTask = Task { [weak self] in
            var wasOnline: Bool?
            for await online in stream {
                guard let self else { break }
                if online, wasOnline != true {
                    backoff.reset()
                    await tick()
                }
                wasOnline = online
            }
        }
    }

    /// One scheduler tick: emits diagnostic bookends and dispatches the two
    /// site-info fetch sweeps (signed-in + signed-out / ownerless accounts).
    ///
    /// Exposed as `internal` so tests can drive it directly (the Timer / asyncAfter
    /// are test-hostile; driving `tick()` lets the test control the clock without
    /// sleeping for real intervals).
    func tick() async {
        let startedAt = Date()

        await diagnostics.record(
            category: .scheduler,
            level: .debug,
            event: "tick.start",
            message: "Scheduler tick started",
            instance: nil,
            metadata: nil
        )

        await fetchSiteInfoAndMyUserInfoForSignedInIfNeeded()
        await fetchSiteInfoForSignedOutIfNeeded()

        let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        await diagnostics.record(
            category: .scheduler,
            level: .debug,
            event: "tick.finish",
            message: "Scheduler tick finished",
            instance: nil,
            metadata: ["durationMs": String(durationMs)]
        )
    }

    // MARK: Site Info

    private func fetchSiteInfo(forInstance actorId: InstanceActorId) async {
        logger.info("Fetching site info for \(actorId.actorId, privacy: .public)")

        // TODO: separate fetching of generic "site info" and account specific info
        // For now we fetch site info as signed out user only,
        // but better would be to fetch site info for each account (to fetch subscriptions)
        // and also extract generic site info from server response.

        let keychainId = accountService.accountForSignedOut(
            forInstance: actorId,
            isServiceAccount: true
        )

        await gatedFetchSiteInfo(forAccountKeychainId: keychainId)
    }

    /// Gate the fetch through the per-account back-off, then record the outcome.
    /// All four per-account call sites funnel here so the back-off state is
    /// authoritative regardless of which sweep triggers the attempt.
    private func gatedFetchSiteInfo(forAccountKeychainId keychainId: String) async {
        guard backoff.shouldAttempt(keychainId: keychainId, now: now()) else { return }
        let succeeded = await fetchSiteInfo(forAccountKeychainId: keychainId)
        backoff.recordResult(keychainId: keychainId, succeeded: succeeded, now: now())
    }

    /// Perform the actual network call for one account. Returns `true` on success,
    /// `false` on any error (the error is still routed to `alertService` so the
    /// existing error-handling and `site.fetchFailed` diagnostic are unchanged).
    private func fetchSiteInfo(forAccountKeychainId keychainId: String) async -> Bool {
        let instance = accountService.instanceActorId(forAccountKeychainId: keychainId)?.hostWithPort
        await diagnostics.record(
            category: .scheduler,
            level: .debug,
            event: "account.fetch",
            message: "Fetching site info for account",
            instance: instance,
            metadata: nil
        )
        do {
            try await accountService
                .lemmyService(forAccountKeychainId: keychainId)
                .fetchSiteInfo()
            return true
        } catch {
            alertService.handle(error, for: .fetchSiteInfo)
            return false
        }
    }

    private func fetchSiteInfoForSignedOutIfNeeded() async {
        // Fetch initial site info, i.e. sites that have never fetched corresponding site info.
        // But only for signed out accounts (signed in accounts site info will be fetched
        // together with subscribed communities).
        let signedOutKeychainIds: [String]
        do {
            signedOutKeychainIds = try await appDatabase.signedOutAccountsAwaitingSiteInfo(now: Date()).map(\.keychainId)
        } catch {
            logger.error("Failed to query signed-out accounts awaiting site info: \(String(describing: error), privacy: .public)")
            signedOutKeychainIds = []
        }
        for keychainId in signedOutKeychainIds {
            await gatedFetchSiteInfo(forAccountKeychainId: keychainId)
        }

        // Fetch initial site info, i.e. sites that have never fetched corresponding site info.
        // But only for sites that we do not have any account for (not even signed out).
        let ownerlessActorIds: [InstanceActorId]
        do {
            ownerlessActorIds = try await appDatabase.ownerlessSitesAwaitingInfo(now: Date()).map(\.actorId)
        } catch {
            logger.error("Failed to query ownerless sites: \(String(describing: error), privacy: .public)")
            ownerlessActorIds = []
        }
        for actorId in ownerlessActorIds {
            await fetchSiteInfo(forInstance: actorId)
        }

        // TODO: Also periodically re-fetch Site info for sites that we do not have a local account for?
    }

    // MARK: Subscribed communities

    /// For signed in accounts periodically re-fetch user info e.g. list of subscribed communities.
    private func fetchSiteInfoAndMyUserInfoForSignedInIfNeeded() async {
        // Fetch initial site info (which includes `MyUserInfo`) for new accounts
        // that we never fetched it before.
        let initialKeychainIds: [String]
        do {
            initialKeychainIds = try await appDatabase.signedInAccountsAwaitingMyUserInfo()
        } catch {
            logger.error("Failed to query signed-in accounts awaiting MyUserInfo: \(String(describing: error), privacy: .public)")
            initialKeychainIds = []
        }
        for keychainId in initialKeychainIds {
            await gatedFetchSiteInfo(forAccountKeychainId: keychainId)
        }

        // Re-fetch info periodically. Check if the data is older than 1 day and fetch.
        let oneDay: TimeInterval = 24 * 60 * 60
        let cutoff = Date().addingTimeInterval(-oneDay)
        let staleKeychainIds: [String]
        do {
            staleKeychainIds = try await appDatabase.signedInAccountsStale(updatedBefore: cutoff)
        } catch {
            logger.error("Failed to query stale signed-in accounts: \(String(describing: error), privacy: .public)")
            staleKeychainIds = []
        }
        for keychainId in staleKeychainIds {
            await gatedFetchSiteInfo(forAccountKeychainId: keychainId)
        }
    }
}
