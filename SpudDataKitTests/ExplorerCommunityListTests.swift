//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Testing
@testable import SpudDataKit

struct ExplorerCommunityListTests {
    /// The Discover directory's data source: CommunityListRows built from the
    /// seeded Explorer community directory.
    @Test
    func explorerCommunityListRows_fromSeed() async throws {
        let appDatabase = try AppDatabase.inMemory()
        await ExplorerService(appDatabase: appDatabase).importSeedsIfNeeded()

        let rows = appDatabase.explorerCommunityListRowsSync()
        #expect(rows.count > 1000, "directory should list the seeded communities")
        #expect(rows.contains { $0.instanceHost == "lemmy.world" }, "well-known instance present")

        let first = try #require(rows.first)
        #expect(!(first.name.isEmpty))
        #expect(!(first.communityUrl.isEmpty))
        #expect(!(first.displayName.isEmpty))
    }

    @Test
    func topExplorerCommunities_rankedByScore() async throws {
        let appDatabase = try AppDatabase.inMemory()
        await ExplorerService(appDatabase: appDatabase).importSeedsIfNeeded()

        let top = appDatabase.topExplorerCommunitiesSync(limit: 10)
        #expect(top.count == 10)
        #expect(top[0].score >= top[9].score, "ordered by score, highest first")
    }
}
