import GRDB
import Testing
@testable import SpudDataKit

struct PendingOperationRecordTests {
    /// Seeds the minimal account graph (instance -> site -> account) and returns the account row id.
    private func seedAccount(_ appDatabase: AppDatabase) async throws -> Int64 {
        try await appDatabase.writer.write { db in
            try db.execute(
                sql: "INSERT INTO instance (actorId, createdAt) VALUES (?, ?)",
                arguments: ["https://test.lemmy", "2026-01-01"]
            )
            let instanceId = db.lastInsertedRowID
            try db.execute(
                sql: "INSERT INTO site (instanceId, createdAt, updatedAt) VALUES (?, ?, ?)",
                arguments: [instanceId, "2026-01-01", "2026-01-01"]
            )
            let siteId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO account (siteId, accountKeychainId, isDefault, isServiceAccount,
                    isSignedOutAccountType, createdAt, updatedAt)
                VALUES (?, ?, 0, 0, 0, ?, ?)
                """, arguments: [siteId, "kc-test", "2026-01-01", "2026-01-01"])
            return db.lastInsertedRowID
        }
    }

    @Test
    func tableExistsAndRecordRoundTrips() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let accountId = try await seedAccount(appDatabase)
        try await appDatabase.writer.write { db in
            var record = PendingOperationRecord(
                accountId: accountId, entityType: "post", entityServerId: 42, kind: "vote",
                desiredState: 1, baseline: nil, attempts: 0, lastError: nil,
                nextAttemptAt: nil, createdAt: 100, updatedAt: 100
            )
            try record.insert(db)
        }
        let fetched = try await appDatabase.writer.read { db in
            try PendingOperationRecord.fetchOne(db)
        }
        #expect(fetched?.entityServerId == 42)
        #expect(fetched?.kind == "vote")
    }

    @Test
    func uniqueConstraintCoalescesPerKindPerTarget() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let accountId = try await seedAccount(appDatabase)
        try await appDatabase.writer.write { db in
            var v = PendingOperationRecord(
                accountId: accountId,
                entityType: "post",
                entityServerId: 42,
                kind: "vote",
                desiredState: 1,
                baseline: nil,
                attempts: 0,
                lastError: nil,
                nextAttemptAt: nil,
                createdAt: 1,
                updatedAt: 1
            )
            try v.insert(db)
            var s = PendingOperationRecord(
                accountId: accountId,
                entityType: "post",
                entityServerId: 42,
                kind: "save",
                desiredState: 1,
                baseline: nil,
                attempts: 0,
                lastError: nil,
                nextAttemptAt: nil,
                createdAt: 1,
                updatedAt: 1
            )
            try s.insert(db) // different kind, same target: allowed
        }
        // Same (account, entity, kind) twice must violate UNIQUE.
        await #expect(throws: (any Error).self) {
            try await appDatabase.writer.write { db in
                var dup = PendingOperationRecord(
                    accountId: accountId,
                    entityType: "post",
                    entityServerId: 42,
                    kind: "vote",
                    desiredState: 1,
                    baseline: nil,
                    attempts: 0,
                    lastError: nil,
                    nextAttemptAt: nil,
                    createdAt: 1,
                    updatedAt: 1
                )
                try dup.insert(db)
            }
        }
    }
}
