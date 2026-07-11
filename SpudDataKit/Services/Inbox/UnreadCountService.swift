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
    private let diagnostics: DiagnosticLogging

    public init(
        accountService: AccountServiceType,
        diagnostics: DiagnosticLogging
    ) {
        self.accountService = accountService
        self.diagnostics = diagnostics
    }

    public func refresh(accountKeychainId: String) async {
        guard !accountKeychainId.isEmpty else { return }

        guard !accountService.isSignedOut(forAccountKeychainId: accountKeychainId) else {
            unreadCount = .zero
            return
        }

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
            unreadCount = count
            // Read `total` directly — never re-sum the per-kind fields: a v4
            // backend reports only a combined total (per-kind are zero there), so
            // summing would log 0 for exactly the instances that report a total.
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
        unreadCount = UnreadCount(
            replies: max(0, unreadCount.replies - replies),
            mentions: max(0, unreadCount.mentions - mentions),
            privateMessages: max(0, unreadCount.privateMessages - privateMessages),
            total: max(0, unreadCount.total - removed)
        )
    }

    public func reset() {
        unreadCount = .zero
    }
}
