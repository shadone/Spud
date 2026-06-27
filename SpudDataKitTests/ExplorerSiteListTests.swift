//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Testing
@testable import SpudDataKit

struct ExplorerSiteListTests {
    /// The instance picker's data source: SiteListRows built from the seeded
    /// Explorer directory, ranked by score, with valid instance identifiers.
    @Test
    func explorerSiteListRows_fromSeed() async throws {
        let appDatabase = try AppDatabase.inMemory()
        await ExplorerService(appDatabase: appDatabase).importSeedsIfNeeded()

        let rows = appDatabase.explorerSiteListRowsSync()
        #expect(rows.count > 100, "picker should list the Explorer directory")
        #expect(rows.contains { $0.hostname == "lemmy.world" }, "well-known instance present")

        let first = try #require(rows.first)
        #expect(!(first.hostname.isEmpty))
        #expect(first.instance.host == first.hostname, "row.instance matches its hostname")
    }
}
