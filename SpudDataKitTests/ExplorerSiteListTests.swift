//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import SpudDataKit

final class ExplorerSiteListTests: XCTestCase {
    /// The instance picker's data source: SiteListRows built from the seeded
    /// Explorer directory, ranked by score, with valid instance identifiers.
    func test_explorerSiteListRows_fromSeed() async throws {
        let appDatabase = try AppDatabase.inMemory()
        await ExplorerService(appDatabase: appDatabase).importSeedsIfNeeded()

        let rows = appDatabase.explorerSiteListRowsSync()
        XCTAssertGreaterThan(rows.count, 100, "picker should list the Explorer directory")
        XCTAssertTrue(rows.contains { $0.hostname == "lemmy.world" }, "well-known instance present")

        let first = try XCTUnwrap(rows.first)
        XCTAssertFalse(first.hostname.isEmpty)
        XCTAssertEqual(first.instance.host, first.hostname, "row.instance matches its hostname")
    }
}
