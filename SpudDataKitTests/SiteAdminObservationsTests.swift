//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import GRDB
import SpudUtilKit
import XCTest
@testable import SpudDataKit

final class SiteAdminObservationsTests: XCTestCase {
    func test_siteAdminsSync_returnsAdminsForInstanceOrdered() throws {
        let appDatabase = try AppDatabase.inMemory()
        let actorId = "https://lemmy.world"
        try appDatabase.writer.write { db in
            var instance = InstanceRecord(actorId: actorId, createdAt: Date(), updatedAt: Date())
            try instance.insert(db)
            var site = SiteRecord(instanceId: instance.id!, name: "Lemmy World")
            try site.insert(db)
            for (i, name) in ["ruud", "milan"].enumerated() {
                var a = SiteAdminRecord(siteId: site.id!, ordinal: i, personActorId: "\(actorId)/u/\(name)", personName: name)
                try a.insert(db)
            }
        }

        let instance = try XCTUnwrap(InstanceActorId(from: actorId))
        let admins = appDatabase.siteAdminsSync(forInstanceActorId: instance)
        XCTAssertEqual(admins.map(\.personName), ["ruud", "milan"])
    }
}
