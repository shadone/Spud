//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

/// Live `MetaCommunityResolving`: resolves a candidate community name through
/// `LemmyService.fetchCommunityInfo`, then reads the mirrored `CommunityRecord`
/// back to build the resolved candidate. Returns nil when the community does
/// not exist on the instance (fetch throws) or cannot be read back.
public struct LiveMetaCommunityResolver: MetaCommunityResolving {
    // `nonisolated(unsafe)`: `AccountServiceType` is `@MainActor`-isolated (so
    // not itself `Sendable`), but `MetaCommunityResolving` is a plain `Sendable`
    // seam called from the `MetaCommunityService` actor. This is safe because
    // every access below goes through `await MainActor.run { ... }` -- the
    // stored reference itself is never read or mutated off the main actor.
    private nonisolated(unsafe) let accountService: AccountServiceType
    private let appDatabase: AppDatabase

    public init(accountService: AccountServiceType, appDatabase: AppDatabase) {
        self.accountService = accountService
        self.appDatabase = appDatabase
    }

    public func resolveCandidate(
        name: String, onHost host: String, forAccountKeychainId keychainId: String
    ) async -> ResolvedMetaCandidate? {
        // `AccountServiceType` is `@MainActor`; hop over once for both reads
        // rather than twice, since `resolveCandidate` is called once per
        // candidate name per instance refresh.
        let (homeHost, lemmyService) = await MainActor.run {
            (
                accountService.instanceActorId(forAccountKeychainId: keychainId)?.hostWithPort,
                accountService.lemmyService(forAccountKeychainId: keychainId)
            )
        }
        // Bare name for a community local to the account's own instance;
        // "name@host" for any other instance.
        let query = (host == homeHost) ? name : "\(name)@\(host)"
        guard let serverId = try? await lemmyService.fetchCommunityInfo(communityName: query) else {
            return nil
        }
        return appDatabase.resolvedMetaCandidateSync(
            forKeychainId: keychainId, serverCommunityId: Int64(serverId)
        )
    }
}
