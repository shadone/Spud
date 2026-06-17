//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import GRDB
import XCTest
@testable import SpudDataKit

final class SiteAdminRecordTests: XCTestCase {
    func test_insertAndFetch_roundTrips() throws {
        let appDatabase = try AppDatabase.inMemory()
        try appDatabase.writer.write { db in
            // A site row is required for the foreign key.
            var instance = InstanceRecord(actorId: "https://lemmy.world", createdAt: Date(), updatedAt: Date())
            try instance.insert(db)
            var site = SiteRecord(instanceId: instance.id!, name: "Lemmy World")
            try site.insert(db)

            var admin = SiteAdminRecord(
                siteId: site.id!, ordinal: 0,
                personActorId: "https://lemmy.world/u/ruud",
                personName: "ruud", displayName: "Ruud", avatarUrl: nil
            )
            try admin.insert(db)

            let fetched = try SiteAdminRecord.fetchAll(db)
            XCTAssertEqual(fetched.count, 1)
            XCTAssertEqual(fetched[0].personName, "ruud")
            XCTAssertEqual(fetched[0].displayName, "Ruud")
            XCTAssertEqual(fetched[0].ordinal, 0)
        }
    }
}
