//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import GRDB
import Testing
@testable import SpudDataKit

struct DiagnosticEventMigrationTests {
    @Test
    func diagnosticEventTableExistsAfterMigration() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let exists = try await appDatabase.writer.read { db in
            try db.tableExists("diagnosticEvent")
        }
        #expect(exists)
    }

    @Test
    func timestampIndexExistsAfterMigration() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let indexes = try await appDatabase.writer.read { db in
            try db.indexes(on: "diagnosticEvent")
        }
        let hasTimestampIndex = indexes.contains { $0.name == "index_diagnosticEvent_on_timestamp" }
        #expect(hasTimestampIndex)
    }
}
