//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import GRDB
import Testing
@testable import SpudDataKit

struct AppDatabaseTests {
    private var sut: AppDatabase

    init() throws {
        sut = try AppDatabase.inMemory()
    }

    @Test
    func migratorCreatesAllExpectedTables() throws {
        let tableNames = try sut.writer.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name"
            )
        }

        let appTables = tableNames.filter {
            !$0.hasPrefix("grdb_") && !$0.hasPrefix("sqlite_") && !$0.hasPrefix("postInteractionFts_")
        }

        #expect(
            Set(appTables) == Set([
                "account",
                "accountFollowedCommunity",
                "comment",
                "commentElement",
                "community",
                "diagnosticEvent",
                "explorerCommunity",
                "explorerDatasetMeta",
                "explorerInstance",
                "favoritedCommunity",
                "feed",
                "instance",
                "instanceMetaCommunity",
                "mutedCommunity",
                "nodeInfo",
                "nodeInfoCache",
                "offlineWebArchive",
                "outboundContent",
                "page",
                "pageElement",
                "person",
                "post",
                "postCrossPost",
                "postInteraction",
                "postInteractionFts",
                "privateMessage",
                "reminder",
                "site",
                "pendingOperation",
                "siteAdmin",
                "voteEvent",
            ])
        )
    }

    @Test
    func instanceRoundTrip() throws {
        let inserted = try sut.writer.write { db -> InstanceRecord in
            var record = InstanceRecord(actorId: "https://lemmy.world")
            try record.insert(db)
            return record
        }
        #expect(inserted.id != nil)

        let fetched = try sut.writer.read { db in
            try InstanceRecord.fetchOne(db, key: inserted.id!)
        }
        #expect(fetched?.actorId == "https://lemmy.world")
    }

    @Test
    func cascadeDeleteFromInstanceClearsDependentRows() throws {
        let (instanceId, accountId) = try sut.writer.write { db -> (Int64, Int64) in
            var instance = InstanceRecord(actorId: "https://lemmy.world")
            try instance.insert(db)

            var site = SiteRecord(instanceId: instance.id!)
            try site.insert(db)

            var account = AccountRecord(
                siteId: site.id!,
                accountKeychainId: "keychain-1"
            )
            try account.insert(db)

            return (instance.id!, account.id!)
        }

        try sut.writer.write { db in
            _ = try InstanceRecord.deleteOne(db, key: instanceId)
        }

        let remainingAccount = try sut.writer.read { db in
            try AccountRecord.fetchOne(db, key: accountId)
        }
        #expect(remainingAccount == nil, "Account should cascade-delete with its site/instance")
    }

    @Test
    func uniqueAccountKeychainIdEnforced() throws {
        let siteId = try sut.writer.write { db -> Int64 in
            var instance = InstanceRecord(actorId: "https://lemmy.world")
            try instance.insert(db)
            var site = SiteRecord(instanceId: instance.id!)
            try site.insert(db)
            return site.id!
        }

        try sut.writer.write { db in
            var account = AccountRecord(siteId: siteId, accountKeychainId: "shared")
            try account.insert(db)
        }

        #expect(throws: (any Error).self) {
            try sut.writer.write { db in
                var dup = AccountRecord(siteId: siteId, accountKeychainId: "shared")
                try dup.insert(db)
            }
        }
    }
}
