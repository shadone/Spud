//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import Observation
import OSLog

private let logger = Logger.inbox

@MainActor
public protocol UnreadCountServiceType: AnyObject {
    /// The latest unread count for the active account. Observable so the inbox
    /// badge updates live. Signed-out accounts report `.zero`.
    var unreadCount: UnreadCount { get }

    /// Refresh the unread count for `accountKeychainId`. No-op (resets to
    /// `.zero`) when the account is signed out. Failures are logged and leave
    /// the previous count in place so a transient network error doesn't blank
    /// the badge.
    func refresh(accountKeychainId: String) async

    /// Adjust the cached count locally after marking items read, so the badge
    /// reflects the change immediately without waiting for a network refresh.
    /// Clamped at zero.
    func decrement(replies: Int, mentions: Int, privateMessages: Int)

    /// Reset the cached count to zero (e.g. after "mark all read").
    func reset()
}

@MainActor
public protocol HasUnreadCountService {
    var unreadCountService: UnreadCountServiceType { get }
}

/// Tracks the unread inbox count for the active account. The inbox content
/// itself is transient (fetched per-screen, like search), but the COUNT is
/// held here and exposed as `@Observable` state so the tab badge can update
/// live: on app foreground, after marking items read, and after sending.
@MainActor
@Observable
public final class UnreadCountService: UnreadCountServiceType {
    public private(set) var unreadCount: UnreadCount = .zero

    @ObservationIgnored
    private let accountService: AccountServiceType

    @ObservationIgnored
    private let appDatabase: AppDatabase

    @ObservationIgnored
    private let diagnostics: DiagnosticLogging

    /// The last-fetched server-side unread count (replies/mentions/DMs),
    /// tracked separately from the blended `unreadCount` so a reminder-count
    /// change (a reminder firing, or the Reminders segment marking its fired
    /// items seen) can recompute the badge total on its own, without waiting
    /// for - or triggering - a network `refresh()`.
    @ObservationIgnored
    private var serverCount: UnreadCount = .zero

    /// The active account's fired-and-unseen reminder count, blended into
    /// `unreadCount.total` so a fired reminder lights the Inbox tab exactly
    /// like an unread reply/mention. Kept live by a standing
    /// `observeUnseenReminderCount` subscription (`observeReminderCount`),
    /// not by polling - the badge reacts immediately to a reconcile, a fresh
    /// fire, or `markRemindersSeen`.
    @ObservationIgnored
    private var reminderUnseenCount: Int = 0

    @ObservationIgnored
    private var reminderCountTask: Task<Void, Never>?
    /// The account currently backing `reminderCountTask` - guards against
    /// tearing down and restarting the observation on every `refresh()` call
    /// for the SAME account (e.g. every Inbox `viewWillAppear`).
    @ObservationIgnored
    private var observedAccountKeychainId: String?

    public init(
        accountService: AccountServiceType,
        appDatabase: AppDatabase,
        diagnostics: DiagnosticLogging
    ) {
        self.accountService = accountService
        self.appDatabase = appDatabase
        self.diagnostics = diagnostics
    }

    public func refresh(accountKeychainId: String) async {
        guard !accountKeychainId.isEmpty else { return }

        guard !accountService.isSignedOut(forAccountKeychainId: accountKeychainId) else {
            stopObservingReminderCount()
            serverCount = .zero
            reminderUnseenCount = 0
            unreadCount = .zero
            return
        }

        observeReminderCount(accountKeychainId: accountKeychainId)

        let instance = accountService.instanceActorId(forAccountKeychainId: accountKeychainId)?.hostWithPort

        await diagnostics.record(
            category: .unread,
            level: .info,
            event: "refresh.start",
            message: "Refreshing unread count",
            instance: instance,
            metadata: nil
        )

        do {
            let count = try await accountService
                .lemmyService(forAccountKeychainId: accountKeychainId)
                .unreadCount()
            serverCount = count
            applyBlendedCount()
            // Read `total` directly — never re-sum the per-kind fields: a v4
            // backend reports only a combined total (per-kind are zero there), so
            // summing would log 0 for exactly the instances that report a total.
            // Logs the server-reported total (not the reminder-blended badge) -
            // this event is about the server refresh specifically.
            let total = count.total
            await diagnostics.record(
                category: .unread,
                level: .info,
                event: "refresh.finish",
                message: "Unread count refreshed",
                instance: instance,
                metadata: ["unreadCount": String(total)]
            )
        } catch {
            logger.error("Unread count refresh failed: \(String(describing: error), privacy: .public)")
            // Leave the previous count in place.
            var metadata: [String: String] = ["error": String(describing: error)]
            if case let .unknownServerError(httpStatus, _) = error as? LemmyApiError {
                metadata["httpStatus"] = String(httpStatus)
            }
            await diagnostics.record(
                category: .unread,
                level: .error,
                event: "refresh.failed",
                message: "Unread count refresh failed: \(error)",
                instance: instance,
                metadata: metadata
            )
        }
    }

    public func decrement(replies: Int, mentions: Int, privateMessages: Int) {
        // Decrement `total` explicitly alongside the per-kind fields: on a v4
        // backend the per-kind fields are always zero and only `total` carries
        // the badge count, so recomputing total from the (zero) per-kind fields
        // would wrongly wipe the badge on the first item marked read.
        let removed = replies + mentions + privateMessages
        serverCount = UnreadCount(
            replies: max(0, serverCount.replies - replies),
            mentions: max(0, serverCount.mentions - mentions),
            privateMessages: max(0, serverCount.privateMessages - privateMessages),
            total: max(0, serverCount.total - removed)
        )
        applyBlendedCount()
    }

    public func reset() {
        // "Mark all read" is a Lemmy-server concept (replies/mentions/DMs);
        // reminders are seen/unseen independently via the Reminders segment,
        // so only the server-side count resets here.
        serverCount = .zero
        applyBlendedCount()
    }

    /// (Re)starts the live `observeUnseenReminderCount` stream for
    /// `accountKeychainId`, unless it's already the account being observed. A
    /// not-yet-imported account (no row to resolve) just zeroes the reminder
    /// contribution rather than blocking the caller.
    private func observeReminderCount(accountKeychainId: String) {
        guard observedAccountKeychainId != accountKeychainId else { return }
        stopObservingReminderCount()

        guard let accountId = appDatabase.accountRowIdSync(forKeychainId: accountKeychainId) else {
            // Don't mark this account as "observed" yet - the account row
            // hasn't landed. Leaving `observedAccountKeychainId` nil lets the
            // next refresh retry `accountRowIdSync` instead of short-circuiting
            // on the guard above forever.
            reminderUnseenCount = 0
            applyBlendedCount()
            return
        }
        observedAccountKeychainId = accountKeychainId

        let appDatabase = appDatabase
        reminderCountTask = Task { @MainActor [weak self] in
            for await count in appDatabase.observeUnseenReminderCount(accountId: accountId) {
                if Task.isCancelled { break }
                self?.reminderUnseenCount = count
                self?.applyBlendedCount()
            }
        }
    }

    private func stopObservingReminderCount() {
        reminderCountTask?.cancel()
        reminderCountTask = nil
        observedAccountKeychainId = nil
    }

    /// Recomputes the published `unreadCount` from the last-known
    /// `serverCount` and `reminderUnseenCount`. The per-kind fields stay
    /// server-only (a reminder is neither a reply, a mention, nor a DM); only
    /// `total` - the badge value `MainWindow.applyUnreadBadge` reads - picks
    /// up the reminder contribution.
    private func applyBlendedCount() {
        unreadCount = UnreadCount(
            replies: serverCount.replies,
            mentions: serverCount.mentions,
            privateMessages: serverCount.privateMessages,
            total: serverCount.total + reminderUnseenCount
        )
    }
}
