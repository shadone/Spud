//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUtilKit

/// The per-account dependency scope: a handle bundling an account's resolved
/// `LemmyService` and immutable facts (signed-out status, home instance) with
/// its durable identifier (`accountKeychainId`).
///
/// Where `DependencyContainer` is the app-lifetime scope, `AccountScope` names
/// the per-account scope that was previously implicit - spread across a bare
/// `accountKeychainId: String` threaded through view models plus repeated
/// `accountService.lemmyService(forAccountKeychainId:)` / `isSignedOut(...)`
/// lookups. Screens that need a Lemmy connection take an `AccountScope` instead
/// of a raw keychain id, so the dependency is resolved once and the requirement
/// is expressed in the type rather than re-derived at every call site.
///
/// Only *immutable* per-account facts live here. Mutable, preference-driven
/// values (default sort/listing type) stay on `AccountService` so a long-lived
/// scope can't go stale.
@MainActor
public struct AccountScope {
    /// The durable identifier of the account this scope belongs to.
    public let accountKeychainId: String

    /// Whether this is a signed-out (anonymous) account. Immutable for the
    /// account's lifetime: signing in creates a *new* account (new keychain id),
    /// so the signed-out status of a given keychain id never changes.
    public let isSignedOut: Bool

    /// The actor id of the account's home instance (e.g. the one behind
    /// `lemmy.world`), or nil if it can't be resolved. Immutable for the
    /// account's lifetime.
    public let instanceActorId: InstanceActorId?

    /// The account's `LemmyService`, talking to its home instance with its
    /// credential (or unauthenticated, for a signed-out account).
    public let lemmyService: LemmyServiceType

    public init(
        accountKeychainId: String,
        isSignedOut: Bool,
        instanceActorId: InstanceActorId?,
        lemmyService: LemmyServiceType
    ) {
        self.accountKeychainId = accountKeychainId
        self.isSignedOut = isSignedOut
        self.instanceActorId = instanceActorId
        self.lemmyService = lemmyService
    }
}

@MainActor
public extension AccountServiceType {
    /// The per-account `AccountScope` for `keychainId`. Reuses the same cached
    /// `LemmyService` as `lemmyService(forAccountKeychainId:)`, so the scope is
    /// a handle over the existing per-account lifecycle - not a parallel one.
    func scope(forAccountKeychainId keychainId: String) -> AccountScope {
        AccountScope(
            accountKeychainId: keychainId,
            isSignedOut: isSignedOut(forAccountKeychainId: keychainId),
            instanceActorId: instanceActorId(forAccountKeychainId: keychainId),
            lemmyService: lemmyService(forAccountKeychainId: keychainId)
        )
    }
}
