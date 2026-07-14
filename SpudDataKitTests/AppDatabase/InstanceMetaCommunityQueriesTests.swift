//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import SpudUtilKit
import Testing
@testable import SpudDataKit

struct InstanceMetaCommunityQueriesTests {
    private let appDatabase: AppDatabase

    init() throws {
        appDatabase = try AppDatabase.inMemory()
    }

    /// `AccountRecord.siteId` is a NOT NULL foreign key to `site`, which in turn
    /// has a NOT NULL foreign key to `instance` — so seeding a bare account
    /// requires standing up an instance and a site first (mirrors the pattern in
    /// `InstanceMetaCommunityRecordTests.makeAccount`).
    private func makeAccount() throws -> Int64 {
        try appDatabase.writer.write { db in
            var instance = InstanceRecord(actorId: "https://example.com")
            try instance.insert(db)

            var site = try SiteRecord(instanceId: #require(instance.id))
            try site.insert(db)

            var account = try AccountRecord(
                siteId: #require(site.id),
                accountKeychainId: "kc-1"
            )
            try account.insert(db)
            return try #require(account.id)
        }
    }

    private func insertCommunity(
        accountId: Int64, serverId: Int64, name: String, actorId: String,
        subscribed: CommunitySubscribedState = .notSubscribed
    ) throws {
        try appDatabase.writer.write { db in
            var c = CommunityRecord(
                accountId: accountId, communityId: serverId, name: name, title: name,
                actorId: actorId, descriptionText: nil, iconUrl: nil, bannerUrl: nil,
                isHidden: false, isLocal: true, isNsfw: false,
                isPostingRestrictedToMods: false, isRemoved: false,
                subscribedState: subscribed.rawValue, numberOfSubscribers: 0,
                numberOfPosts: 0, numberOfComments: 0, communityCreatedDate: nil,
                communityUpdatedDate: nil, createdAt: Date(), updatedAt: Date()
            )
            try c.insert(db)
        }
    }

    @Test
    func replaceThenFreshnessReturnsLatest() throws {
        let accountId = try makeAccount()
        appDatabase.replaceMetaCommunitiesSync(
            forAccountId: accountId, instanceHost: "tchncs.de",
            entries: [.init(communityActorId: "a", confidence: .high, reason: .strongKeyword)]
        )
        #expect(appDatabase.metaCommunityFreshnessSync(forAccountId: accountId, instanceHost: "tchncs.de") != nil)
        #expect(appDatabase.metaCommunityFreshnessSync(forAccountId: accountId, instanceHost: "other.de") == nil)
    }

    @Test
    func replaceIsAtomicSwap() throws {
        let accountId = try makeAccount()
        appDatabase.replaceMetaCommunitiesSync(
            forAccountId: accountId, instanceHost: "tchncs.de",
            entries: [
                .init(communityActorId: "a", confidence: .high, reason: .strongKeyword),
                .init(communityActorId: "b", confidence: .low, reason: .broadKeyword),
            ]
        )
        appDatabase.replaceMetaCommunitiesSync(
            forAccountId: accountId, instanceHost: "tchncs.de",
            entries: [.init(communityActorId: "a", confidence: .high, reason: .strongKeyword)]
        )
        let count = try appDatabase.writer.read { db in
            try InstanceMetaCommunityRecord
                .filter(Column("accountId") == accountId)
                .fetchCount(db)
        }
        #expect(count == 1)
    }

    @Test
    func observeJoinsCommunityAndFavourite() async throws {
        let accountId = try makeAccount()
        try insertCommunity(
            accountId: accountId,
            serverId: 42,
            name: "meta",
            actorId: "https://tchncs.de/c/meta",
            subscribed: .subscribed
        )
        appDatabase.favoriteCommunitySync(forKeychainId: "kc-1", communityActorId: "https://tchncs.de/c/meta")
        appDatabase.replaceMetaCommunitiesSync(
            forAccountId: accountId, instanceHost: "tchncs.de",
            entries: [.init(communityActorId: "https://tchncs.de/c/meta", confidence: .high, reason: .strongKeyword)]
        )

        var iterator = appDatabase.observeMetaCommunities(
            forAccountId: accountId, instanceHost: "tchncs.de"
        ).makeAsyncIterator()
        let items = try #require(await iterator.next())
        #expect(items.count == 1)
        let item = try #require(items.first)
        #expect(item.serverCommunityId == 42)
        #expect(item.name == "meta")
        #expect(item.confidence == .high)
        #expect(item.subscribedState == .subscribed)
        #expect(item.isFavorite)
    }
}
