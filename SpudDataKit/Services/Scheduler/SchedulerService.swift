//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
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
        await pollActivityRemindersSweep()

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

    /// Outcome of a single site-info fetch. Distinct from a bare `Bool` so the
    /// signed-out / ownerless sweeps can tell a permanent (4xx) failure — which
    /// counts toward the persisted give-up — apart from a transient one.
    private enum SiteInfoOutcome {
        case success
        case permanentFailure
        case transientFailure
    }

    /// Gate a signed-in fetch through the in-memory per-account back-off, then
    /// record the outcome. Signed-in sweeps still use `SchedulerBackoff`; the
    /// signed-out / ownerless sweeps use the persisted give-up state instead and
    /// call `fetchSiteInfoOutcome` + `recordSiteInfoResult` directly
    /// (see `fetchSiteInfoForSignedOutIfNeeded`).
    private func gatedFetchSiteInfo(forAccountKeychainId keychainId: String) async {
        guard backoff.shouldAttempt(keychainId: keychainId, now: now()) else { return }
        let outcome = await fetchSiteInfoOutcome(forAccountKeychainId: keychainId)
        backoff.recordResult(keychainId: keychainId, succeeded: outcome == .success, now: now())
    }

    /// Perform the actual network call for one account and classify the result.
    /// The error is still routed to `alertService` (so the existing error handling
    /// and the `site.fetchFailed` diagnostic emitted inside `LemmyService` are
    /// unchanged); its permanence is classified with the shared `OutboxFailureClass`
    /// (as `RequestRetry` does): a 4xx is permanent (drives give-up); 5xx / timeout /
    /// offline is transient. `isOnline: true` is safe because a genuine offline
    /// failure surfaces as a `URLError`, which `OutboxFailureClass` treats as
    /// transient regardless of the flag.
    private func fetchSiteInfoOutcome(forAccountKeychainId keychainId: String) async -> SiteInfoOutcome {
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
            return .success
        } catch {
            alertService.handle(error, for: .fetchSiteInfo)
            return OutboxFailureClass.classify(error, isOnline: true) == .permanent
                ? .permanentFailure
                : .transientFailure
        }
    }

    /// Record the persisted give-up state for a site after a signed-out / ownerless
    /// fetch, and emit `site.giveUp` the first time the consecutive-permanent count
    /// reaches the threshold (after which the sweep queries stop selecting the site).
    private func recordSiteInfoResult(_ outcome: SiteInfoOutcome, siteId: Int64, instance: String?) async {
        switch outcome {
        case .success:
            // Give-up state is reset inside `SiteImporter` on the successful import;
            // nothing to do here.
            break
        case .transientFailure:
            do {
                try appDatabase.recordSiteInfoTransientFailure(siteId: siteId, now: now())
            } catch {
                logger.error("Failed to record site-info transient failure: \(String(describing: error), privacy: .public)")
            }
        case .permanentFailure:
            let count: Int
            do {
                count = try appDatabase.recordSiteInfoPermanentFailure(siteId: siteId, now: now())
            } catch {
                logger.error("Failed to record site-info permanent failure: \(String(describing: error), privacy: .public)")
                count = 0
            }
            if count == AppDatabase.siteInfoGiveUpThreshold {
                await diagnostics.record(
                    category: .site,
                    level: .notice,
                    event: "site.giveUp",
                    message: "Stopped fetching site info after repeated permanent failures",
                    instance: instance,
                    metadata: ["failureCount": String(count)]
                )
            }
        }
    }

    private func fetchSiteInfoForSignedOutIfNeeded() async {
        // Fetch initial site info, i.e. sites that have never fetched corresponding
        // site info, but only for signed out accounts (signed in accounts' site
        // info is fetched together with subscribed communities). The query itself
        // gates on the persisted give-up state (back-off window + give-up
        // threshold), so no in-memory `SchedulerBackoff` is consulted here.
        let signedOut: [(keychainId: String, siteId: Int64)]
        do {
            signedOut = try await appDatabase.signedOutAccountsAwaitingSiteInfo(now: now())
        } catch {
            logger.error("Failed to query signed-out accounts awaiting site info: \(String(describing: error), privacy: .public)")
            signedOut = []
        }
        for row in signedOut {
            let instance = accountService.instanceActorId(forAccountKeychainId: row.keychainId)?.hostWithPort
            let outcome = await fetchSiteInfoOutcome(forAccountKeychainId: row.keychainId)
            await recordSiteInfoResult(outcome, siteId: row.siteId, instance: instance)
        }

        // Fetch initial site info for sites that we do not have any account for
        // (not even signed out).
        let ownerless: [(actorId: InstanceActorId, siteId: Int64)]
        do {
            ownerless = try await appDatabase.ownerlessSitesAwaitingInfo(now: now())
        } catch {
            logger.error("Failed to query ownerless sites: \(String(describing: error), privacy: .public)")
            ownerless = []
        }
        for row in ownerless {
            let keychainId = accountService.accountForSignedOut(
                forInstance: row.actorId,
                isServiceAccount: true
            )
            let outcome = await fetchSiteInfoOutcome(forAccountKeychainId: keychainId)
            await recordSiteInfoResult(outcome, siteId: row.siteId, instance: row.actorId.hostWithPort)
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

    // MARK: Activity reminder poll (Post Reminders Phase 2)

    /// Drives `ReminderService.pollDueActivityReminders` once per pollable
    /// account per tick - the foreground half of the "When there are new
    /// comments" follow, whole-post AND comment-subtree (spec §5.1/§5.3;
    /// Phase 3 added the subtree scope). Background polling
    /// (`BGAppRefreshTask`) is a later phase; this only runs while the app is
    /// in the foreground and the 5-minute tick fires.
    ///
    /// Accounts are enumerated via `pollableAccountKeychainIds()` - every
    /// non-service account, BOTH signed-in and signed-out. Unlike the two
    /// site-info sweeps (which only cover signed-in accounts, or gate
    /// signed-out accounts on an unfetched/back-off site-info state), an
    /// activity follow can be set while browsing signed out - `LemmyService.
    /// fetchPostInfo` (`getPost`) is anonymous, and Phase-1 TIME reminders
    /// already work signed-out - so this sweep reaches every real account, not
    /// just `signedInAccountKeychainIds()` (which the signed-in site-info sweep
    /// still uses, unchanged).
    ///
    /// Accounts are polled SEQUENTIALLY, not concurrently: `pollDueActivityReminders`
    /// runs on the account's `ReminderService` actor, and firing two overlapping
    /// polls for the same account (e.g. from a re-entrant tick) could double-fire
    /// the same due reminder before the first poll's re-arm write lands. One poll
    /// per account per tick keeps that impossible by construction.
    ///
    /// Only accounts with at least one due activity reminder do any network
    /// work - `pollDueActivityReminders` early-returns on an empty due list -
    /// so an idle tick (the common case, most posts have no activity follow)
    /// is cheap: one GRDB read per account, no network call (`lemmyService(forAccountKeychainId:)`
    /// itself is a cheap sync read - it's the network `fetchPostInfo` that's
    /// skipped when nothing is due).
    private func pollActivityRemindersSweep() async {
        await diagnostics.record(
            category: .reminder,
            level: .debug,
            event: "poll.sweep.start",
            message: "Activity reminder poll sweep started",
            instance: nil,
            metadata: nil
        )

        let keychainIds: [String]
        do {
            keychainIds = try await appDatabase.pollableAccountKeychainIds()
        } catch {
            logger.error("Failed to query pollable accounts for activity reminder poll: \(String(describing: error), privacy: .public)")
            keychainIds = []
        }

        for keychainId in keychainIds {
            // Bind to locals before building the `@Sendable` fetcher closure below,
            // so it captures these values directly rather than implicitly capturing
            // `self` (a `@MainActor`, non-`Sendable` class) through the property
            // accesses - required for this to type-check under Swift 6 strict
            // concurrency.
            let appDatabase = appDatabase
            let lemmy = accountService.lemmyService(forAccountKeychainId: keychainId)
            // Phase 3: the fetcher branches on `rootCommentServerId` so a
            // subtree follow is counted from the root comment's `child_count`
            // instead of the post's `numberOfComments`. This sweep still only
            // ever creates whole-post follows itself (the comment-menu entry
            // point that creates subtree follows is a later task), but a
            // subtree row created via that future entry point is polled
            // correctly by this same sweep already.
            let fetcher: @Sendable (Int64, Int64) async -> Int? = { postServerId, rootCommentServerId in
                // Best-effort: a failed refresh just means the poll falls back to
                // the previously-cached comment count (read below regardless)
                // rather than skipping the account entirely - `pollDueActivityReminders`
                // itself treats a `nil` fetcher result (not a thrown error) as
                // "fetch failed" and bumps `nextCheckAt` without firing.
                if rootCommentServerId == ReminderRecord.wholePostSentinel {
                    try? await lemmy.fetchPostInfo(serverPostId: Lemmy.PostID(postServerId))
                    return appDatabase.postNumberOfCommentsSync(forKeychainId: keychainId, serverPostId: postServerId)
                } else {
                    // `LemmyServiceType` exposes only a post-scoped `fetchComments`
                    // (no `parentID`-scoped overload at this pinned LemmyKit
                    // version), so refresh the whole tree under the post - it
                    // re-imports every comment, including the subtree's root,
                    // and `CommentImporter` persists each one's server
                    // `child_count` (Task 1), so `commentChildCountSync` below
                    // reads a fresh value afterward. Costs more than a
                    // parent-scoped fetch would, but is the cheapest option
                    // that exists today without a LemmyKit release + pin bump.
                    // The sort order is irrelevant here (only `child_count` is
                    // read back, the ordering is never rendered), so `.Hot` is
                    // used as an arbitrary fixed choice.
                    try? await lemmy.fetchComments(serverPostId: Lemmy.PostID(postServerId), sortType: .Hot)
                    return appDatabase.commentChildCountSync(forKeychainId: keychainId, serverCommentId: rootCommentServerId)
                }
            }

            await accountService
                .reminderService(forAccountKeychainId: keychainId)
                .pollDueActivityReminders(asOf: now(), commentCountFetcher: fetcher)
        }

        await diagnostics.record(
            category: .reminder,
            level: .debug,
            event: "poll.sweep.finish",
            message: "Activity reminder poll sweep finished",
            instance: nil,
            metadata: ["accountCount": String(keychainIds.count)]
        )
    }
}
