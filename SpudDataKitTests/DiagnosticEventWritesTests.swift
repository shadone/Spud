//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudDataKit

struct DiagnosticEventWritesTests {
    // MARK: - Helpers

    /// Inserts 3 canonical events into the database.
    ///
    /// - debug / outbox  / timestamp = t+0
    /// - notice / scheduler / timestamp = t+1
    /// - error / outbox  / timestamp = t+2  (message contains "403")
    private func seedThreeEvents(in db: AppDatabase, baseTimestamp: Double = 1_000_000) async throws {
        try await db.insertDiagnosticEvent(DiagnosticEventRecord(
            timestamp: baseTimestamp,
            category: DiagnosticCategory.outbox.rawValue,
            level: DiagnosticLevel.debug.rawValue,
            event: "enqueued",
            message: "Item enqueued"
        ))
        try await db.insertDiagnosticEvent(DiagnosticEventRecord(
            timestamp: baseTimestamp + 1,
            category: DiagnosticCategory.scheduler.rawValue,
            level: DiagnosticLevel.notice.rawValue,
            event: "scheduled",
            message: "Task scheduled"
        ))
        try await db.insertDiagnosticEvent(DiagnosticEventRecord(
            timestamp: baseTimestamp + 2,
            category: DiagnosticCategory.outbox.rawValue,
            level: DiagnosticLevel.error.rawValue,
            event: "fetchFailed",
            message: "HTTP error",
            instance: "https://lemmy.world",
            metadata: "{\"status\":\"403\"}"
        ))
    }

    // MARK: - insertDiagnosticEvent

    @Test
    func insert_assignsRowId() async throws {
        let db = try AppDatabase.inMemory()
        var record = DiagnosticEventRecord(
            timestamp: 1_000_000,
            category: DiagnosticCategory.outbox.rawValue,
            level: DiagnosticLevel.info.rawValue,
            event: "test",
            message: "hello"
        )
        try await db.insertDiagnosticEvent(record)
        // After insert the record is re-fetched via recentDiagnosticEvents;
        // the id-assignment contract is tested via the fetched row having an id.
        let rows = try await db.recentDiagnosticEvents(DiagnosticLogFilter())
        #expect(rows.count == 1)
        #expect(rows[0].id != nil)
    }

    // MARK: - recentDiagnosticEvents — minimumLevel

    @Test
    func recentDiagnosticEvents_minimumLevel_filtersDebug() async throws {
        let db = try AppDatabase.inMemory()
        try await seedThreeEvents(in: db)

        let filter = DiagnosticLogFilter(minimumLevel: .notice)
        let rows = try await db.recentDiagnosticEvents(filter)

        // Should include notice + error only (not debug).
        #expect(rows.count == 2)
        // Newest first: error (t+2) before notice (t+1).
        #expect(rows[0].levelEnum == .error)
        #expect(rows[1].levelEnum == .notice)
    }

    @Test
    func recentDiagnosticEvents_defaultFilter_returnsAll() async throws {
        let db = try AppDatabase.inMemory()
        try await seedThreeEvents(in: db)

        let rows = try await db.recentDiagnosticEvents(DiagnosticLogFilter())
        #expect(rows.count == 3)
    }

    // MARK: - recentDiagnosticEvents — newestFirst ordering

    @Test
    func recentDiagnosticEvents_orderedNewestFirst() async throws {
        let db = try AppDatabase.inMemory()
        try await seedThreeEvents(in: db, baseTimestamp: 2_000_000)

        let rows = try await db.recentDiagnosticEvents(DiagnosticLogFilter())
        #expect(rows.count == 3)
        // Timestamps should be descending.
        #expect(rows[0].timestamp > rows[1].timestamp)
        #expect(rows[1].timestamp > rows[2].timestamp)
    }

    // MARK: - recentDiagnosticEvents — categories filter

    @Test
    func recentDiagnosticEvents_categoryFilter_returnsOnlyMatchingCategory() async throws {
        let db = try AppDatabase.inMemory()
        try await seedThreeEvents(in: db)

        let filter = DiagnosticLogFilter(categories: [.outbox])
        let rows = try await db.recentDiagnosticEvents(filter)

        // outbox has 2 events (debug + error); scheduler has 1 (notice).
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0.categoryEnum == .outbox })
    }

    @Test
    func recentDiagnosticEvents_categoryFilter_emptyResultWhenNoneMatch() async throws {
        let db = try AppDatabase.inMemory()
        try await seedThreeEvents(in: db)

        let filter = DiagnosticLogFilter(categories: [.lifecycle])
        let rows = try await db.recentDiagnosticEvents(filter)
        // swiftformat:disable:next isEmpty
        #expect(rows.count == 0)
    }

    @Test
    func recentDiagnosticEvents_emptyCategoriesSet_returnsAll() async throws {
        // An empty set must mean "no category filter = all categories", the same as nil.
        let db = try AppDatabase.inMemory()
        try await seedThreeEvents(in: db)

        let filter = DiagnosticLogFilter(categories: [])
        let rows = try await db.recentDiagnosticEvents(filter)
        #expect(rows.count == 3)
    }

    // MARK: - recentDiagnosticEvents — searchText

    @Test
    func recentDiagnosticEvents_searchText_matchesMetadata() async throws {
        let db = try AppDatabase.inMemory()
        try await seedThreeEvents(in: db)

        let filter = DiagnosticLogFilter(searchText: "403")
        let rows = try await db.recentDiagnosticEvents(filter)

        // Only e3 has "403" in metadata.
        #expect(rows.count == 1)
        #expect(rows[0].message == "HTTP error")
        #expect(rows[0].event == "fetchFailed")
    }

    @Test
    func recentDiagnosticEvents_searchText_matchesMessage() async throws {
        let db = try AppDatabase.inMemory()
        try await seedThreeEvents(in: db)

        let filter = DiagnosticLogFilter(searchText: "scheduled")
        let rows = try await db.recentDiagnosticEvents(filter)

        #expect(rows.count == 1)
        #expect(rows[0].levelEnum == .notice)
    }

    @Test
    func recentDiagnosticEvents_searchText_emptyStringReturnsAll() async throws {
        let db = try AppDatabase.inMemory()
        try await seedThreeEvents(in: db)

        let filter = DiagnosticLogFilter(searchText: "")
        let rows = try await db.recentDiagnosticEvents(filter)
        #expect(rows.count == 3)
    }

    @Test
    func recentDiagnosticEvents_searchText_whitespaceOnlyReturnsAll() async throws {
        let db = try AppDatabase.inMemory()
        try await seedThreeEvents(in: db)

        let filter = DiagnosticLogFilter(searchText: "   ")
        let rows = try await db.recentDiagnosticEvents(filter)
        #expect(rows.count == 3)
    }

    // MARK: - recentDiagnosticEvents — limit

    @Test
    func recentDiagnosticEvents_limitIsRespected() async throws {
        let db = try AppDatabase.inMemory()
        try await seedThreeEvents(in: db)

        let filter = DiagnosticLogFilter(limit: 2)
        let rows = try await db.recentDiagnosticEvents(filter)
        #expect(rows.count == 2)
    }

    // MARK: - pruneDiagnosticEvents — maxRows

    @Test
    func prune_maxRows_leavesNewestRows() async throws {
        let db = try AppDatabase.inMemory()
        let base: Double = 3_000_000
        try await seedThreeEvents(in: db, baseTimestamp: base)

        // Prune to newest 2.
        try await db.pruneDiagnosticEvents(now: base + 10, maxRows: 2)

        let rows = try await db.recentDiagnosticEvents(DiagnosticLogFilter())
        #expect(rows.count == 2)
        // The two newest are error (t+2) and notice (t+1).
        let levels = Set(rows.compactMap(\.levelEnum))
        #expect(levels.contains(.error))
        #expect(levels.contains(.notice))
        #expect(!levels.contains(.debug))
    }

    // MARK: - pruneDiagnosticEvents — maxAgeSeconds

    @Test
    func prune_maxAgeSeconds_dropsOldRow() async throws {
        let db = try AppDatabase.inMemory()
        let now: Double = 4_000_000
        let fifteenDays: Double = 15 * 24 * 3600

        // Insert a 15-day-old event.
        try await db.insertDiagnosticEvent(DiagnosticEventRecord(
            timestamp: now - fifteenDays,
            category: DiagnosticCategory.scheduler.rawValue,
            level: DiagnosticLevel.info.rawValue,
            event: "old",
            message: "Old event"
        ))

        // Insert a recent event.
        try await db.insertDiagnosticEvent(DiagnosticEventRecord(
            timestamp: now - 60,
            category: DiagnosticCategory.scheduler.rawValue,
            level: DiagnosticLevel.info.rawValue,
            event: "recent",
            message: "Recent event"
        ))

        // Default maxAgeSeconds is 14 * 24 * 3600 (14 days).
        try await db.pruneDiagnosticEvents(now: now)

        let rows = try await db.recentDiagnosticEvents(DiagnosticLogFilter())
        #expect(rows.count == 1)
        #expect(rows[0].event == "recent")
    }

    // MARK: - clearDiagnosticEvents

    @Test
    func clear_emptiesTable() async throws {
        let db = try AppDatabase.inMemory()
        try await seedThreeEvents(in: db)

        try await db.clearDiagnosticEvents()

        let rows = try await db.recentDiagnosticEvents(DiagnosticLogFilter())
        // swiftformat:disable:next isEmpty
        #expect(rows.count == 0)
    }
}
