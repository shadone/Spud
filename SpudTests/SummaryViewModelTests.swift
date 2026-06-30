//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit
import Testing
@testable import Spud

/// Tests for `SummaryViewModel`.
///
/// All tests use a fixed `asOf` date so results are deterministic. The
/// in-memory database starts empty (early/unpopulated state).
@MainActor
struct SummaryViewModelTests {
    /// A fixed reference date: 2025-03-24T00:00:00Z (Monday).
    private static let fixedAsOf = Date(timeIntervalSince1970: 1_742_774_400)

    private func makeViewModel(db: AppDatabase? = nil) throws -> SummaryViewModel {
        let appDatabase = try db ?? AppDatabase.inMemory()
        return SummaryViewModel(
            appDatabase: appDatabase,
            accountId: 1,
            personRowId: nil,
            asOf: Self.fixedAsOf
        )
    }

    /// Seeds a minimal instance → site → person → account chain into an empty
    /// in-memory database. Required before inserting `voteEvent` rows, which
    /// carry an FK (`accountId REFERENCES account(id) ON DELETE CASCADE`).
    ///
    /// Returns the GRDB-assigned accountId (always 1 in a fresh in-memory DB).
    @discardableResult
    private func seedMinimalAccount(in appDatabase: AppDatabase) throws -> Int64 {
        try appDatabase.writer.write { db in
            try db.execute(
                sql: "INSERT INTO instance (actorId, createdAt) VALUES ('https://lemmy.world', ?)",
                arguments: [Date()]
            )
            let instanceId = db.lastInsertedRowID
            try db.execute(
                sql: "INSERT INTO site (instanceId, createdAt, updatedAt) VALUES (?, ?, ?)",
                arguments: [instanceId, Date(), Date()]
            )
            let siteId = db.lastInsertedRowID
            try db.execute(
                sql: """
                    INSERT INTO person (siteId, personId, name, displayName,
                        numberOfPosts, numberOfComments,
                        personCreatedDate, createdAt, updatedAt)
                    VALUES (?, 101, 'test_user', NULL, 0, 0, ?, ?, ?)
                    """,
                arguments: [siteId, Date(), Date(), Date()]
            )
            let personRowId = db.lastInsertedRowID
            try db.execute(
                sql: """
                    INSERT INTO account
                        (siteId, personId, accountKeychainId,
                         isDefault, isServiceAccount, isSignedOutAccountType,
                         createdAt, updatedAt)
                    VALUES (?, ?, 'test-account', 1, 0, 0, ?, ?)
                    """,
                arguments: [siteId, personRowId, Date(), Date()]
            )
            return db.lastInsertedRowID
        }
    }

    // MARK: - Initial state (empty DB)

    @Test
    func initialMetricIsAll() throws {
        let vm = try makeViewModel()
        #expect(vm.selectedMetric == .all)
    }

    @Test
    func initialStatsIsNil() throws {
        let vm = try makeViewModel()
        // stats is populated by the async observation; before start() it is nil.
        #expect(vm.stats == nil)
    }

    @Test
    func initialSeriesHasCorrectMetricAndZeroTotal() throws {
        let vm = try makeViewModel()
        #expect(vm.series.metric == .all)
        #expect(vm.series.total == 0)
    }

    @Test
    func initialSeriesHas18Weeks() throws {
        let vm = try makeViewModel()
        #expect(vm.series.weeks.count == 18)
    }

    @Test
    func initialSeriesEachWeekHas7Days() throws {
        let vm = try makeViewModel()
        for week in vm.series.weeks {
            #expect(week.count == 7)
        }
    }

    @Test
    func initialExtrasHaveZeroStreak() throws {
        let vm = try makeViewModel()
        #expect(vm.extras.streakDays == 0)
    }

    // MARK: - Metric switching

    @Test
    func selectMetricUpdatesSelectedMetric() throws {
        let vm = try makeViewModel()
        vm.selectMetric(.reads)
        #expect(vm.selectedMetric == .reads)
    }

    @Test
    func selectMetricUpdatesSeriesMetric() throws {
        let vm = try makeViewModel()
        vm.selectMetric(.reads)
        #expect(vm.series.metric == .reads)
    }

    @Test
    func selectVotesMetricUpdatesSeriesMetric() throws {
        let vm = try makeViewModel()
        vm.selectMetric(.votes)
        #expect(vm.series.metric == .votes)
    }

    @Test
    func selectSameMetricIsNoop() throws {
        let vm = try makeViewModel()
        let before = vm.series
        vm.selectMetric(.all) // already .all
        let after = vm.series
        #expect(before == after)
    }

    @Test
    func metricCycleReturnsToAll() throws {
        let vm = try makeViewModel()
        vm.selectMetric(.reads)
        vm.selectMetric(.votes)
        vm.selectMetric(.all)
        #expect(vm.selectedMetric == .all)
        #expect(vm.series.metric == .all)
    }

    // MARK: - Populated state

    @Test
    func seriesHasCorrectTotalAfterActivity() throws {
        let db = try AppDatabase.inMemory()

        // Seed the FK chain first, then a vote event on the reference date.
        let accountId = try seedMinimalAccount(in: db)
        let votedAt = Self.fixedAsOf
        try db.writer.write { dbConn in
            let epochSec = Int64(votedAt.timeIntervalSince1970)
            try dbConn.execute(
                sql: """
                    INSERT INTO voteEvent (accountId, entityType, entityServerId, voteAction, votedAt, communityName)
                    VALUES (?, 'post', 42, 1, ?, NULL)
                    """,
                arguments: [accountId, epochSec]
            )
        }

        let vm = SummaryViewModel(
            appDatabase: db,
            accountId: accountId,
            personRowId: nil,
            asOf: Self.fixedAsOf
        )

        vm.selectMetric(.votes)
        // The vote falls in the 18-week window; total should be 1.
        #expect(vm.series.total == 1)
    }

    @Test
    func readsMetricDoesNotCountVotes() throws {
        let db = try AppDatabase.inMemory()

        // Seed the FK chain first, then one vote event.
        let accountId = try seedMinimalAccount(in: db)
        try db.writer.write { dbConn in
            let epochSec = Int64(Self.fixedAsOf.timeIntervalSince1970)
            try dbConn.execute(
                sql: """
                    INSERT INTO voteEvent (accountId, entityType, entityServerId, voteAction, votedAt, communityName)
                    VALUES (?, 'post', 99, 1, ?, NULL)
                    """,
                arguments: [accountId, epochSec]
            )
        }

        let vm = SummaryViewModel(
            appDatabase: db,
            accountId: accountId,
            personRowId: nil,
            asOf: Self.fixedAsOf
        )

        vm.selectMetric(.reads)
        // Vote events must not appear in the reads metric.
        #expect(vm.series.total == 0)
    }
}
