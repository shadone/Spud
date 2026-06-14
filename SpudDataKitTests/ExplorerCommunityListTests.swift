//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import SpudDataKit

final class ExplorerCommunityListTests: XCTestCase {
    /// The Discover directory's data source: CommunityListRows built from the
    /// seeded Explorer community directory.
    func test_explorerCommunityListRows_fromSeed() async throws {
        let appDatabase = try AppDatabase.inMemory()
        await ExplorerService(appDatabase: appDatabase).importSeedsIfNeeded()

        let rows = appDatabase.explorerCommunityListRowsSync()
        XCTAssertGreaterThan(rows.count, 1000, "directory should list the seeded communities")
        XCTAssertTrue(rows.contains { $0.instanceHost == "lemmy.world" }, "well-known instance present")

        let first = try XCTUnwrap(rows.first)
        XCTAssertFalse(first.name.isEmpty)
        XCTAssertFalse(first.communityUrl.isEmpty)
        XCTAssertFalse(first.displayName.isEmpty)
    }

    func test_topExplorerCommunities_rankedByScore() async throws {
        let appDatabase = try AppDatabase.inMemory()
        await ExplorerService(appDatabase: appDatabase).importSeedsIfNeeded()

        let top = appDatabase.topExplorerCommunitiesSync(limit: 10)
        XCTAssertEqual(top.count, 10)
        XCTAssertGreaterThanOrEqual(top[0].score, top[9].score, "ordered by score, highest first")
    }
}
