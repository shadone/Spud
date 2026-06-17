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

    func test_observeSiteAdmins_emitsInitialThenUpdatesOnChange() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let actorId = "https://lemmy.world"
        let instance = try XCTUnwrap(InstanceActorId(from: actorId))

        let siteId: Int64 = try await appDatabase.writer.write { db in
            var inst = InstanceRecord(actorId: actorId, createdAt: Date(), updatedAt: Date())
            try inst.insert(db)
            var site = SiteRecord(instanceId: inst.id!, name: "Lemmy World")
            try site.insert(db)
            var owner = SiteAdminRecord(siteId: site.id!, ordinal: 0, personActorId: "\(actorId)/u/ruud", personName: "ruud")
            try owner.insert(db)
            return site.id!
        }

        var iterator = appDatabase.observeSiteAdmins(forInstanceActorId: instance).makeAsyncIterator()

        // The first emission reflects the seeded admin.
        let initial = await iterator.next()
        XCTAssertEqual(initial?.map(\.personName), ["ruud"])

        // Inserting another admin emits a fresh, ordered snapshot.
        try await appDatabase.writer.write { db in
            var admin = SiteAdminRecord(siteId: siteId, ordinal: 1, personActorId: "\(actorId)/u/milan", personName: "milan")
            try admin.insert(db)
        }

        let updated = await iterator.next()
        XCTAssertEqual(updated?.map(\.personName), ["ruud", "milan"])
    }
}
