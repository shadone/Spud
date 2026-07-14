//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import OSLog
import SpudUtilKit

/// One classified "meta" community to cache for `(account, instanceHost)`.
/// Identity only — live subscribe / favourite state is joined at render time
/// from `community` / `favoritedCommunity`, never duplicated here.
public struct MetaCommunityCacheEntry: Sendable, Equatable {
    public let communityActorId: String
    public let confidence: MetaConfidence
    public let reason: MetaReason

    public init(communityActorId: String, confidence: MetaConfidence, reason: MetaReason) {
        self.communityActorId = communityActorId
        self.confidence = confidence
        self.reason = reason
    }
}

/// A meta community joined with its live `community` + `favoritedCommunity`
/// state, ready to render in a list.
public struct MetaCommunityListItem: Sendable, Equatable, Identifiable {
    /// The community's server-side id, also the SwiftUI identity.
    public let id: Int64
    public var serverCommunityId: Int64 {
        id
    }

    public let name: String
    public let title: String?
    public let communityActorId: String
    public let iconUrl: String?
    public let confidence: MetaConfidence
    public let subscribedState: CommunitySubscribedState
    public let isFavorite: Bool

    /// A `public` struct only gets an `internal` synthesized memberwise
    /// initializer, so callers outside `SpudDataKit` (e.g. view models and
    /// their tests) need this explicit one to construct a value directly
    /// rather than only ever reading one back from `observeMetaCommunities`.
    public init(
        id: Int64,
        name: String,
        title: String?,
        communityActorId: String,
        iconUrl: String?,
        confidence: MetaConfidence,
        subscribedState: CommunitySubscribedState,
        isFavorite: Bool
    ) {
        self.id = id
        self.name = name
        self.title = title
        self.communityActorId = communityActorId
        self.iconUrl = iconUrl
        self.confidence = confidence
        self.subscribedState = subscribedState
        self.isFavorite = isFavorite
    }
}

public extension AppDatabase {
    /// Atomically replaces the cached meta-community set for `(accountId,
    /// instanceHost)` with `entries` — a delete-then-insert in a single write
    /// transaction, so observers never see a transient empty state between the
    /// old and new set.
    func replaceMetaCommunitiesSync(
        forAccountId accountId: Int64,
        instanceHost: String,
        entries: [MetaCommunityCacheEntry]
    ) {
        do {
            try writer.write { db in
                try InstanceMetaCommunityRecord
                    .filter(Column("accountId") == accountId)
                    .filter(Column("instanceHost") == instanceHost)
                    .deleteAll(db)
                let now = Date()
                for entry in entries {
                    var record = InstanceMetaCommunityRecord(
                        accountId: accountId,
                        instanceHost: instanceHost,
                        communityActorId: entry.communityActorId,
                        confidence: entry.confidence.rawValue,
                        reason: entry.reason.rawValue,
                        discoveredAt: now
                    )
                    try record.insert(db)
                }
            }
        } catch {
            Logger.appDatabase.error("replaceMetaCommunitiesSync failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// The most recent `discoveredAt` among the cached meta communities for
    /// `(accountId, instanceHost)`, or nil if the cache is empty — used to
    /// decide whether a re-classification pass is due.
    func metaCommunityFreshnessSync(
        forAccountId accountId: Int64,
        instanceHost: String
    ) -> Date? {
        do {
            return try writer.read { db in
                try Date.fetchOne(db, sql: """
                    SELECT MAX(discoveredAt) FROM instanceMetaCommunity
                    WHERE accountId = ? AND instanceHost = ?
                    """, arguments: [accountId, instanceHost])
            }
        } catch {
            Logger.appDatabase.error("metaCommunityFreshnessSync failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Stream of the cached meta communities for `(accountId, instanceHost)`,
    /// joined live against `community` (name/title/icon/subscribedState) and
    /// `favoritedCommunity` (isFavorite). Yields immediately on subscription and
    /// again on every change to any of the three tables. High-confidence entries
    /// sort first, then alphabetically by name.
    func observeMetaCommunities(
        forAccountId accountId: Int64,
        instanceHost: String
    ) -> AsyncStream<[MetaCommunityListItem]> {
        let observation = ValueObservation
            .tracking { db -> [MetaCommunityListItem] in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT c.communityId AS serverId,
                           c.name AS name,
                           c.title AS title,
                           c.actorId AS actorId,
                           c.iconUrl AS iconUrl,
                           c.subscribedState AS subscribedState,
                           m.confidence AS confidence,
                           (fc.id IS NOT NULL) AS isFavorite
                    FROM instanceMetaCommunity m
                    JOIN community c
                        ON c.actorId = m.communityActorId AND c.accountId = m.accountId
                    LEFT JOIN favoritedCommunity fc
                        ON fc.communityActorId = m.communityActorId AND fc.accountId = m.accountId
                    WHERE m.accountId = ? AND m.instanceHost = ?
                    ORDER BY (m.confidence = 'high') DESC, LOWER(c.name) ASC
                    """, arguments: [accountId, instanceHost])
                return rows.map { row in
                    MetaCommunityListItem(
                        id: row["serverId"],
                        name: row["name"] ?? "",
                        title: row["title"],
                        communityActorId: row["actorId"] ?? "",
                        iconUrl: row["iconUrl"],
                        confidence: MetaConfidence(rawValue: row["confidence"] ?? "low") ?? .low,
                        subscribedState: CommunitySubscribedState(rawValue: row["subscribedState"] ?? "") ?? .notSubscribed,
                        isFavorite: (row["isFavorite"] as Int64? ?? 0) != 0
                    )
                }
            }
            .removeDuplicates()
        return makeStream(observation: observation)
    }

    /// Read back a just-mirrored community as a `ResolvedMetaCandidate`, used by
    /// `LiveMetaCommunityResolver` after `LemmyService.fetchCommunityInfo` has
    /// mirrored the `CommunityRecord`. Returns nil when the account or community
    /// row can't be found, or the community has no `actorId` / its `actorId`
    /// carries no parseable host.
    func resolvedMetaCandidateSync(
        forKeychainId keychainId: String, serverCommunityId: Int64
    ) -> ResolvedMetaCandidate? {
        do {
            return try writer.read { db -> ResolvedMetaCandidate? in
                guard
                    let accountId = try AccountRecord
                    .filter(Column("accountKeychainId") == keychainId)
                    .fetchOne(db)?.id,
                    let community = try CommunityRecord
                    .filter(Column("accountId") == accountId)
                    .filter(Column("communityId") == serverCommunityId)
                    .fetchOne(db),
                    let actorId = community.actorId,
                    let host = URL(string: actorId)?.host
                else { return nil }
                return ResolvedMetaCandidate(
                    name: community.name ?? "", title: community.title,
                    actorId: actorId, instanceHost: host
                )
            }
        } catch {
            Logger.appDatabase.error("resolvedMetaCandidateSync failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
