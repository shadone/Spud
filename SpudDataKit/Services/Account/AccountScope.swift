//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// The per-account dependency scope: a handle bundling an account's resolved
/// `LemmyService` with its durable identifier (`accountKeychainId`).
///
/// Where `DependencyContainer` is the app-lifetime scope, `AccountScope` names
/// the per-account scope that was previously implicit - spread across a bare
/// `accountKeychainId: String` threaded through view models plus repeated
/// `accountService.lemmyService(forAccountKeychainId:)` lookups. Screens that
/// need a Lemmy connection take an `AccountScope` instead of a raw keychain id,
/// so the dependency is resolved once and the requirement is expressed in the
/// type rather than re-derived at every call site.
@MainActor
public struct AccountScope {
    /// The durable identifier of the account this scope belongs to.
    public let accountKeychainId: String

    /// The account's `LemmyService`, talking to its home instance with its
    /// credential (or unauthenticated, for a signed-out account).
    public let lemmyService: LemmyServiceType

    public init(accountKeychainId: String, lemmyService: LemmyServiceType) {
        self.accountKeychainId = accountKeychainId
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
            lemmyService: lemmyService(forAccountKeychainId: keychainId)
        )
    }
}
