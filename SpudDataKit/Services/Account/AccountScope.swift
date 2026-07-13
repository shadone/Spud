//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUtilKit

/// The per-account facade over `AccountServiceType`: account-scoped operations
/// bound to one account, reached without threading an `accountKeychainId`
/// through every call.
///
/// Where `DependencyContainer` is the app-lifetime scope, `AccountScope` names
/// the per-account scope that was previously implicit - a bare
/// `accountKeychainId: String` threaded through view models plus repeated
/// `accountService.lemmyService(forAccountKeychainId:)` / `isSignedOut(...)`
/// lookups. A screen takes an `AccountScope` instead of
/// `(accountService, accountKeychainId)` and reads `scope.lemmyService` /
/// `scope.isSignedOut`.
///
/// Accessors resolve **live** against `AccountService` on each read (the
/// underlying `LemmyService` is itself cached per account), so a long-lived
/// scope never serves a stale snapshot: `isSignedOut` reflects current account
/// state and `lemmyService` resolves the current cached service. Construction is
/// free - no I/O happens until an accessor is used.
@MainActor
public struct AccountScope {
    /// The durable identifier of the account this scope is bound to.
    public let accountKeychainId: String

    private let accountService: AccountServiceType

    public init(accountKeychainId: String, accountService: AccountServiceType) {
        self.accountKeychainId = accountKeychainId
        self.accountService = accountService
    }

    /// The account's `LemmyService` (cached per account), talking to its home
    /// instance with its credential (or unauthenticated, for a signed-out
    /// account).
    public var lemmyService: LemmyServiceType {
        accountService.lemmyService(forAccountKeychainId: accountKeychainId)
    }

    /// The account's `ReminderService` (cached per account) - set/remove time
    /// reminders and reconcile overdue ones. Used by the "Remind Me…" menu
    /// (post detail + feed), the Inbox "Reminders" segment, and the
    /// launch/foreground reconcile trigger.
    public var reminderService: ReminderService {
        accountService.reminderService(forAccountKeychainId: accountKeychainId)
    }

    /// Whether this is a signed-out (anonymous) account. Read live, so sign-in
    /// gates fail safe even if the account is removed out from under the scope.
    public var isSignedOut: Bool {
        accountService.isSignedOut(forAccountKeychainId: accountKeychainId)
    }

    /// The actor id of the account's home instance (e.g. the one behind
    /// `lemmy.world`), or nil if it can't be resolved.
    public var instanceActorId: InstanceActorId? {
        accountService.instanceActorId(forAccountKeychainId: accountKeychainId)
    }

    /// What this account's home instance supports (fail-open when unknown).
    /// Read live on every access — after the instance upgrades and a getSite
    /// import records the new version, existing scopes see the new value.
    public var capabilities: InstanceCapabilities {
        accountService.instanceCapabilities(forAccountKeychainId: accountKeychainId)
    }

    /// A stream of permanent outbox failures (e.g. an expired session) for the
    /// account's optimistic vote/save/hide mutations, so a screen can surface the
    /// rollback. Forwards the account `LemmyService`'s outbox failure stream.
    public func outboxFailureEvents() async -> AsyncStream<OutboxFailure> {
        await lemmyService.outboxFailureEvents()
    }

    /// Drains any operations persisted in this account's outbox right now,
    /// retrying vote/save/hide mutations left pending by a previous session or
    /// held while offline. Used as a foreground / launch retry trigger.
    public func drainPendingOutbox() async {
        await lemmyService.drainPendingOutbox()
    }

    /// A stream of permanent composer failures for compositions enqueued under
    /// this account. Forwards the account `LemmyService`'s composer failure
    /// stream.
    public func composerFailureEvents() async -> AsyncStream<ComposerOutboxFailure> {
        await lemmyService.composerFailureEvents()
    }

    /// A stream of composer successes for compositions delivered under this
    /// account. Forwards the account `LemmyService`'s composer success stream.
    public func composerSuccessEvents() async -> AsyncStream<ComposerOutboxSuccess> {
        await lemmyService.composerSuccessEvents()
    }
}

@MainActor
public extension AccountServiceType {
    /// The per-account `AccountScope` for `keychainId` - a lightweight, zero-I/O
    /// facade bound to this account.
    func scope(forAccountKeychainId keychainId: String) -> AccountScope {
        AccountScope(accountKeychainId: keychainId, accountService: self)
    }
}
