//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import SpudDataKit

final class ExplorerSeedTests: XCTestCase {
    /// Verifies the bundled Explorer seed resources are present, decompress,
    /// decode, and import into the directory tables.
    func test_seedImportsBundledDirectory() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let service = ExplorerService(appDatabase: appDatabase)

        await service.importSeedsIfNeeded()

        let instanceCount = appDatabase.explorerInstanceCountSync()
        let communityCount = appDatabase.explorerCommunityCountSync()
        XCTAssertGreaterThan(instanceCount, 100, "instance seed should import hundreds of instances")
        XCTAssertGreaterThan(communityCount, 1000, "community seed should import thousands of communities")

        // A row carries real parsed fields, not just defaults.
        let instances = appDatabase.topExplorerInstancesSync(limit: instanceCount)
        XCTAssertTrue(instances.contains { $0.baseurl == "lemmy.world" }, "lemmy.world should be present")
        XCTAssertTrue(instances.contains { $0.usersTotal > 0 }, "at least one instance has a user count")
    }

    /// Importing twice must not duplicate rows (empty-guard + replace-on-conflict).
    func test_seedIsIdempotent() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let service = ExplorerService(appDatabase: appDatabase)

        await service.importSeedsIfNeeded()
        let firstInstances = appDatabase.explorerInstanceCountSync()
        let firstCommunities = appDatabase.explorerCommunityCountSync()

        await service.importSeedsIfNeeded()
        XCTAssertEqual(appDatabase.explorerInstanceCountSync(), firstInstances)
        XCTAssertEqual(appDatabase.explorerCommunityCountSync(), firstCommunities)
    }
}
