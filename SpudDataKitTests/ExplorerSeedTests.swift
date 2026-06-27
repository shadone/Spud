//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Testing
@testable import SpudDataKit

struct ExplorerSeedTests {
    /// Verifies the bundled Explorer seed resources are present, decompress,
    /// decode, and import into the directory tables.
    @Test
    func seedImportsBundledDirectory() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let service = ExplorerService(appDatabase: appDatabase)

        await service.importSeedsIfNeeded()

        let instanceCount = appDatabase.explorerInstanceCountSync()
        let communityCount = appDatabase.explorerCommunityCountSync()
        #expect(instanceCount > 100, "instance seed should import hundreds of instances")
        #expect(communityCount > 1000, "community seed should import thousands of communities")

        // A row carries real parsed fields, not just defaults.
        let instances = appDatabase.topExplorerInstancesSync(limit: instanceCount)
        #expect(instances.contains { $0.baseurl == "lemmy.world" }, "lemmy.world should be present")
        #expect(instances.contains { $0.usersTotal > 0 }, "at least one instance has a user count")
    }

    /// Importing twice must not duplicate rows (empty-guard + replace-on-conflict).
    @Test
    func seedIsIdempotent() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let service = ExplorerService(appDatabase: appDatabase)

        await service.importSeedsIfNeeded()
        let firstInstances = appDatabase.explorerInstanceCountSync()
        let firstCommunities = appDatabase.explorerCommunityCountSync()

        await service.importSeedsIfNeeded()
        #expect(appDatabase.explorerInstanceCountSync() == firstInstances)
        #expect(appDatabase.explorerCommunityCountSync() == firstCommunities)
    }
}
