//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import Testing
@testable import SpudDataKit

/// Tests for the heatmap + extras data layer:
/// - `AppDatabase.heatmapSeries(accountId:personRowId:metric:asOf:)`
/// - `AppDatabase.summaryExtras(accountId:personRowId:asOf:)`
///
/// All fixtures use fixed dates; no test reads the wall clock. The fixed
/// reference date is `asOf = 2025-03-24 00:00 UTC` (Monday), chosen because
/// it makes the week-grid alignment trivial to reason about:
///   weeks[17][0] = 2025-03-24 (Monday, asOf's Monday)
///   weeks[0][0]  = 2024-11-25 (Monday, 17 weeks earlier)
///
/// The UTC Gregorian calendar with Monday as week-start matches the
/// implementation's calendar; day-bucketing is consistent.
@Suite(.serialized)
struct HeatmapQueriesTests {
    // MARK: - Fixed reference date

    /// 2025-03-24 00:00 UTC (a Monday). Used as `asOf` throughout.
    ///
    /// epoch 1,742,774,400 = March 24, 2025 00:00 UTC. Verified to be Monday.
    static let asOf = Date(timeIntervalSince1970: 1_742_774_400)

    /// UTC Gregorian calendar with Monday as the first day of the week.
    /// Mirrors the implementation's internal calendar exactly.
    static let utcCal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2 // Monday
        return c
    }()

    /// The Monday that starts asOf's own week (equals asOf since asOf is itself a Monday).
    static var weekStart: Date {
        let comps = utcCal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: asOf)
        return utcCal.date(from: comps)!
    }

    /// The first day of the 18-week window (17 weeks before `weekStart`).
    static var windowStart: Date {
        utcCal.date(byAdding: .weekOfYear, value: -17, to: weekStart)!
    }

    /// Returns the date that is `weekOffset` weeks and `dayOffset` days after
    /// `windowStart`. Use to construct fixture dates for specific grid cells.
    static func cellDate(week weekOffset: Int, day dayOffset: Int) -> Date {
        let d = utcCal.date(byAdding: .weekOfYear, value: weekOffset, to: windowStart)!
        return utcCal.date(byAdding: .day, value: dayOffset, to: d)!
    }

    // MARK: - Seed helpers (pattern from SummaryStatsTests)

    private static func seedAccount(
        _ db: Database,
        host: String = "test.instance"
    ) throws -> (accountId: Int64, siteId: Int64) {
        try db.execute(
            sql: "INSERT INTO instance (actorId, createdAt) VALUES (?, ?)",
            arguments: ["https://\(host)", Date()]
        )
        let instanceId = db.lastInsertedRowID
        try db.execute(
            sql: "INSERT INTO site (instanceId, createdAt, updatedAt) VALUES (?, ?, ?)",
            arguments: [instanceId, Date(), Date()]
        )
        let siteId = db.lastInsertedRowID
        try db.execute(
            sql: """
                INSERT INTO account (siteId, accountKeychainId, isDefault, isServiceAccount,
                                     isSignedOutAccountType, createdAt, updatedAt)
                VALUES (?, ?, 1, 0, 0, ?, ?)
                """,
            arguments: [siteId, "kc-\(host)", Date(), Date()]
        )
        let accountId = db.lastInsertedRowID
        return (accountId, siteId)
    }

    private static func seedPerson(
        _ db: Database,
        siteId: Int64,
        serverPersonId: Int64 = 1
    ) throws -> Int64 {
        try db.execute(
            sql: """
                INSERT INTO person (siteId, personId, name, isAdmin, isBanned,
                                    isBotAccount, isDeleted, isLocal, numberOfPosts,
                                    numberOfComments, createdAt, updatedAt)
                VALUES (?, ?, 'alice', 0, 0, 0, 0, 0, 0, 0, ?, ?)
                """,
            arguments: [siteId, serverPersonId, Date(), Date()]
        )
        return db.lastInsertedRowID
    }

    private static func seedCommunity(
        _ db: Database,
        accountId: Int64,
        serverCommunityId: Int64 = 1,
        name: String = "swift"
    ) throws -> Int64 {
        try db.execute(
            sql: """
                INSERT INTO community (accountId, communityId, name, actorId, isHidden, isLocal, isNsfw,
                                       isPostingRestrictedToMods, isRemoved, subscribedState,
                                       numberOfSubscribers, numberOfPosts, numberOfComments, createdAt, updatedAt)
                VALUES (?, ?, ?, 'https://test.instance/c/\(name)', 0, 0, 0, 0, 0, 'NotSubscribed', 0, 0, 0, ?, ?)
                """,
            arguments: [accountId, serverCommunityId, name, Date(), Date()]
        )
        return db.lastInsertedRowID
    }

    /// Inserts a `postInteraction` row with `lastOpenedAt` set to the given date.
    private static func insertRead(
        _ db: Database,
        accountId: Int64,
        postServerId: Int64,
        lastOpenedAt: Date
    ) throws {
        var record = PostInteractionRecord(
            accountId: accountId,
            postServerId: postServerId,
            lastOpenedAt: lastOpenedAt
        )
        try record.insert(db)
    }

    /// Inserts a `voteEvent` row with `votedAt` set to the given date's epoch.
    private static func insertVote(
        _ db: Database,
        accountId: Int64,
        entityServerId: Int64,
        votedAt: Date,
        communityName: String? = nil,
        communityActorId: String? = nil
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO voteEvent
                    (accountId, entityType, entityServerId, voteAction, votedAt,
                     communityName, communityActorId)
                VALUES (?, 'post', ?, 1, ?, ?, ?)
                """,
            arguments: [accountId, entityServerId, votedAt.timeIntervalSince1970, communityName, communityActorId]
        )
    }

    /// Inserts a `post` row with `published` set to the given date.
    private static func insertAuthoredPost(
        _ db: Database,
        accountId: Int64,
        communityId: Int64,
        creatorId: Int64,
        serverPostId: Int64,
        published: Date
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO post (accountId, communityId, creatorId, postId, title, originalPostUrl,
                                  score, numberOfUpvotes, numberOfDownvotes, numberOfComments,
                                  isRead, isSaved, isHidden, isRemoved, isLocked,
                                  isFeaturedCommunity, isFeaturedLocal, isDeleted,
                                  published, createdAt, updatedAt)
                VALUES (?, ?, ?, ?, 'Post \(serverPostId)', 'https://t.st/\(serverPostId)',
                        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, ?, ?, ?)
                """,
            arguments: [accountId, communityId, creatorId, serverPostId, published, Date(), Date()]
        )
    }

    // MARK: - heatmapSeries — grid structure

    @Test
    func heatmapSeries_emptyDB_returns18x7Grid() async throws {
        let db = try AppDatabase.inMemory()
        let accountId = try await db.writer.write { try Self.seedAccount($0).accountId }
        let series = try db.heatmapSeries(
            accountId: accountId,
            personRowId: nil,
            metric: .reads,
            asOf: Self.asOf
        )
        #expect(series.weeks.count == 18)
        #expect(series.weeks.allSatisfy { $0.count == 7 })
    }

    @Test
    func heatmapSeries_emptyDB_allBucketZero() async throws {
        let db = try AppDatabase.inMemory()
        let accountId = try await db.writer.write { try Self.seedAccount($0).accountId }
        let series = try db.heatmapSeries(
            accountId: accountId,
            personRowId: nil,
            metric: .reads,
            asOf: Self.asOf
        )
        let allZero = series.weeks.allSatisfy { week in week.allSatisfy { $0.bucket == 0 } }
        #expect(allZero)
    }

    @Test
    func heatmapSeries_emptyDB_totalIsZero() async throws {
        let db = try AppDatabase.inMemory()
        let accountId = try await db.writer.write { try Self.seedAccount($0).accountId }
        let series = try db.heatmapSeries(
            accountId: accountId,
            personRowId: nil,
            metric: .reads,
            asOf: Self.asOf
        )
        #expect(series.total == 0)
    }

    @Test
    func heatmapSeries_week0Day0_isWindowStart() async throws {
        let db = try AppDatabase.inMemory()
        let accountId = try await db.writer.write { try Self.seedAccount($0).accountId }
        let series = try db.heatmapSeries(
            accountId: accountId,
            personRowId: nil,
            metric: .reads,
            asOf: Self.asOf
        )
        // weeks[0][0] must be the Monday 17 weeks before asOf's Monday
        #expect(series.weeks[0][0].date == Self.windowStart)
    }

    @Test
    func heatmapSeries_week17Day0_isAsOfMonday() async throws {
        let db = try AppDatabase.inMemory()
        let accountId = try await db.writer.write { try Self.seedAccount($0).accountId }
        let series = try db.heatmapSeries(
            accountId: accountId,
            personRowId: nil,
            metric: .reads,
            asOf: Self.asOf
        )
        // weeks[17][0] is the Monday of asOf's week — equals asOf since asOf is Monday
        #expect(series.weeks[17][0].date == Self.weekStart)
    }

    // MARK: - heatmapSeries reads — day cell placement

    @Test
    func heatmapSeries_reads_singleReadLandsInCorrectCell() async throws {
        let db = try AppDatabase.inMemory()
        // Seed one read on weeks[5][2] (6th week, Wednesday = day index 2)
        let targetDate = Self.cellDate(week: 5, day: 2)
        let accountId = try await db.writer.write { db -> Int64 in
            let (accId, _) = try Self.seedAccount(db)
            // Noon UTC to avoid DST edge cases
            let noonUTC = targetDate.addingTimeInterval(12 * 3600)
            try Self.insertRead(db, accountId: accId, postServerId: 1, lastOpenedAt: noonUTC)
            return accId
        }
        let series = try db.heatmapSeries(
            accountId: accountId,
            personRowId: nil,
            metric: .reads,
            asOf: Self.asOf
        )
        #expect(series.weeks[5][2].count == 1)
        #expect(series.weeks[5][2].bucket == 1) // 1 read → bucket 1
        // All other cells must be zero
        let otherCounts = series.weeks.enumerated().flatMap { wIdx, week in
            week.enumerated().compactMap { dIdx, day -> Int? in
                wIdx == 5 && dIdx == 2 ? nil : day.count
            }
        }
        #expect(otherCounts.allSatisfy { $0 == 0 })
    }

    @Test
    func heatmapSeries_reads_totalEqualsSumOfAllDayCounts() async throws {
        let db = try AppDatabase.inMemory()
        let d1 = Self.cellDate(week: 0, day: 0)
        let d2 = Self.cellDate(week: 3, day: 4)
        let accountId = try await db.writer.write { db -> Int64 in
            let (accId, _) = try Self.seedAccount(db)
            try Self.insertRead(db, accountId: accId, postServerId: 1, lastOpenedAt: d1)
            try Self.insertRead(db, accountId: accId, postServerId: 2, lastOpenedAt: d2)
            try Self.insertRead(db, accountId: accId, postServerId: 3, lastOpenedAt: d2.addingTimeInterval(3600))
            return accId
        }
        let series = try db.heatmapSeries(
            accountId: accountId,
            personRowId: nil,
            metric: .reads,
            asOf: Self.asOf
        )
        #expect(series.total == 3)
    }

    @Test
    func heatmapSeries_reads_activityOutsideWindowIgnored() async throws {
        let db = try AppDatabase.inMemory()
        // Insert a read 1 day before the window start (should be ignored)
        let beforeWindow = Self.windowStart.addingTimeInterval(-86400)
        let accountId = try await db.writer.write { db -> Int64 in
            let (accId, _) = try Self.seedAccount(db)
            try Self.insertRead(db, accountId: accId, postServerId: 99, lastOpenedAt: beforeWindow)
            return accId
        }
        let series = try db.heatmapSeries(
            accountId: accountId,
            personRowId: nil,
            metric: .reads,
            asOf: Self.asOf
        )
        #expect(series.total == 0)
    }

    // MARK: - heatmapSeries reads — bucket thresholds

    @Test
    func heatmapSeries_reads_bucketThresholds() async throws {
        // Seed days with 0, 1, 3, 6, 10 reads and verify bucket mapping:
        //   day 0 → 0 reads  → bucket 0 (implicit, no fixture)
        //   day 1 → 1 read   → bucket 1
        //   day 2 → 3 reads  → bucket 2
        //   day 3 → 6 reads  → bucket 3
        //   day 4 → 10 reads → bucket 4
        let db = try AppDatabase.inMemory()
        let baseWeek = 2
        let dates: [Int: Date] = [
            1: Self.cellDate(week: baseWeek, day: 1),
            2: Self.cellDate(week: baseWeek, day: 2),
            3: Self.cellDate(week: baseWeek, day: 3),
            4: Self.cellDate(week: baseWeek, day: 4),
        ]
        let counts: [Int: Int] = [1: 1, 2: 3, 3: 6, 4: 10]

        let accountId = try await db.writer.write { db -> Int64 in
            let (accId, _) = try Self.seedAccount(db)
            var serverId: Int64 = 100
            for (dayIdx, date) in dates {
                let n = counts[dayIdx]!
                for _ in 0..<n {
                    try Self.insertRead(db, accountId: accId, postServerId: serverId, lastOpenedAt: date)
                    serverId += 1
                }
            }
            return accId
        }
        let series = try db.heatmapSeries(
            accountId: accountId,
            personRowId: nil,
            metric: .reads,
            asOf: Self.asOf
        )
        #expect(series.weeks[baseWeek][0].bucket == 0) // 0 reads
        #expect(series.weeks[baseWeek][1].bucket == 1) // 1 read
        #expect(series.weeks[baseWeek][2].bucket == 2) // 3 reads
        #expect(series.weeks[baseWeek][3].bucket == 3) // 6 reads
        #expect(series.weeks[baseWeek][4].bucket == 4) // 10 reads
    }

    // MARK: - heatmapSeries votes

    @Test
    func heatmapSeries_votes_voteEventLandsInCorrectCell() async throws {
        let db = try AppDatabase.inMemory()
        let targetDate = Self.cellDate(week: 10, day: 5) // Saturday of week 10
        let accountId = try await db.writer.write { db -> Int64 in
            let (accId, _) = try Self.seedAccount(db)
            let noonUTC = targetDate.addingTimeInterval(12 * 3600)
            try Self.insertVote(db, accountId: accId, entityServerId: 1, votedAt: noonUTC)
            return accId
        }
        let series = try db.heatmapSeries(
            accountId: accountId,
            personRowId: nil,
            metric: .votes,
            asOf: Self.asOf
        )
        #expect(series.weeks[10][5].count == 1)
        #expect(series.weeks[10][5].bucket == 1)
    }

    @Test
    func heatmapSeries_votes_emptyWhenNoVoteEvents() async throws {
        let db = try AppDatabase.inMemory()
        let accountId = try await db.writer.write { try Self.seedAccount($0).accountId }
        let series = try db.heatmapSeries(
            accountId: accountId,
            personRowId: nil,
            metric: .votes,
            asOf: Self.asOf
        )
        #expect(series.total == 0)
        let allZero = series.weeks.allSatisfy { $0.allSatisfy { $0.bucket == 0 } }
        #expect(allZero)
    }

    // MARK: - heatmapSeries all

    @Test
    func heatmapSeries_all_sumsReadsAndVotesOnSameDay() async throws {
        let db = try AppDatabase.inMemory()
        let targetDate = Self.cellDate(week: 7, day: 1) // Tuesday of week 7
        let accountId = try await db.writer.write { db -> Int64 in
            let (accId, _) = try Self.seedAccount(db)
            let noonUTC = targetDate.addingTimeInterval(12 * 3600)
            // 2 reads + 2 votes = 4 on the same day → bucket 2 (3-5)
            try Self.insertRead(db, accountId: accId, postServerId: 1, lastOpenedAt: noonUTC)
            try Self.insertRead(db, accountId: accId, postServerId: 2, lastOpenedAt: noonUTC.addingTimeInterval(60))
            try Self.insertVote(db, accountId: accId, entityServerId: 10, votedAt: noonUTC.addingTimeInterval(120))
            try Self.insertVote(db, accountId: accId, entityServerId: 11, votedAt: noonUTC.addingTimeInterval(180))
            return accId
        }
        let series = try db.heatmapSeries(
            accountId: accountId,
            personRowId: nil,
            metric: .all,
            asOf: Self.asOf
        )
        #expect(series.weeks[7][1].count == 4)
        #expect(series.weeks[7][1].bucket == 2) // 3-5 → bucket 2
    }

    @Test
    func heatmapSeries_all_includesAuthoredPostsWhenPersonRowIdProvided() async throws {
        let db = try AppDatabase.inMemory()
        let targetDate = Self.cellDate(week: 4, day: 3) // Thursday of week 4
        let (accountId, personRowId) = try await db.writer.write { db -> (Int64, Int64) in
            let (accId, siteId) = try Self.seedAccount(db)
            let personId = try Self.seedPerson(db, siteId: siteId)
            let commId = try Self.seedCommunity(db, accountId: accId)
            let noonUTC = targetDate.addingTimeInterval(12 * 3600)
            try Self.insertAuthoredPost(
                db, accountId: accId, communityId: commId, creatorId: personId,
                serverPostId: 1, published: noonUTC
            )
            return (accId, personId)
        }
        let series = try db.heatmapSeries(
            accountId: accountId,
            personRowId: personRowId,
            metric: .all,
            asOf: Self.asOf
        )
        #expect(series.weeks[4][3].count == 1)
        #expect(series.weeks[4][3].bucket == 1)
    }

    @Test
    func heatmapSeries_all_authoredPostsIgnoredWhenPersonRowIdNil() async throws {
        let db = try AppDatabase.inMemory()
        let targetDate = Self.cellDate(week: 4, day: 3)
        let accountId = try await db.writer.write { db -> Int64 in
            let (accId, siteId) = try Self.seedAccount(db)
            let personId = try Self.seedPerson(db, siteId: siteId)
            let commId = try Self.seedCommunity(db, accountId: accId)
            let noonUTC = targetDate.addingTimeInterval(12 * 3600)
            try Self.insertAuthoredPost(
                db, accountId: accId, communityId: commId, creatorId: personId,
                serverPostId: 1, published: noonUTC
            )
            return accId
        }
        let series = try db.heatmapSeries(
            accountId: accountId,
            personRowId: nil, // nil → authored posts excluded
            metric: .all,
            asOf: Self.asOf
        )
        #expect(series.total == 0)
    }

    // MARK: - heatmapSeries — account isolation

    @Test
    func heatmapSeries_reads_accountIsolation() async throws {
        let db = try AppDatabase.inMemory()
        let targetDate = Self.cellDate(week: 8, day: 0)
        let (accA, accB) = try await db.writer.write { db -> (Int64, Int64) in
            let (accIdA, _) = try Self.seedAccount(db, host: "alpha.test")
            let (accIdB, _) = try Self.seedAccount(db, host: "beta.test")
            let noonUTC = targetDate.addingTimeInterval(12 * 3600)
            // Account A: 2 reads
            try Self.insertRead(db, accountId: accIdA, postServerId: 1, lastOpenedAt: noonUTC)
            try Self.insertRead(db, accountId: accIdA, postServerId: 2, lastOpenedAt: noonUTC.addingTimeInterval(60))
            // Account B: 5 reads
            for i in Int64(10)..<15 {
                try Self.insertRead(
                    db, accountId: accIdB, postServerId: i,
                    lastOpenedAt: noonUTC.addingTimeInterval(Double(i) * 60)
                )
            }
            return (accIdA, accIdB)
        }
        let seriesA = try db.heatmapSeries(accountId: accA, personRowId: nil, metric: .reads, asOf: Self.asOf)
        let seriesB = try db.heatmapSeries(accountId: accB, personRowId: nil, metric: .reads, asOf: Self.asOf)
        #expect(seriesA.total == 2)
        #expect(seriesB.total == 5)
    }

    // MARK: - summaryExtras — streak

    @Test
    func summaryExtras_streak_zeroWhenNoActivity() async throws {
        let db = try AppDatabase.inMemory()
        let accountId = try await db.writer.write { try Self.seedAccount($0).accountId }
        let extras = try db.summaryExtras(accountId: accountId, personRowId: nil, asOf: Self.asOf)
        #expect(extras.streakDays == 0)
    }

    @Test
    func summaryExtras_streak_oneWhenOnlyAsOfHasActivity() async throws {
        let db = try AppDatabase.inMemory()
        // Activity only on asOf's calendar day
        let noonOnAsOf = Self.asOf.addingTimeInterval(12 * 3600)
        let accountId = try await db.writer.write { db -> Int64 in
            let (accId, _) = try Self.seedAccount(db)
            try Self.insertRead(db, accountId: accId, postServerId: 1, lastOpenedAt: noonOnAsOf)
            return accId
        }
        let extras = try db.summaryExtras(accountId: accountId, personRowId: nil, asOf: Self.asOf)
        #expect(extras.streakDays == 1)
    }

    @Test
    func summaryExtras_streak_countsConsecutiveDaysEndingAtAsOf() async throws {
        let db = try AppDatabase.inMemory()
        // Activity on asOf, asOf-1, asOf-2 (3 consecutive days)
        let d0 = Self.asOf.addingTimeInterval(12 * 3600)
        let d1 = Self.asOf.addingTimeInterval(-86400 + 12 * 3600) // yesterday noon
        let d2 = Self.asOf.addingTimeInterval(-2 * 86400 + 12 * 3600) // day before yesterday noon
        let accountId = try await db.writer.write { db -> Int64 in
            let (accId, _) = try Self.seedAccount(db)
            try Self.insertRead(db, accountId: accId, postServerId: 1, lastOpenedAt: d0)
            try Self.insertRead(db, accountId: accId, postServerId: 2, lastOpenedAt: d1)
            try Self.insertRead(db, accountId: accId, postServerId: 3, lastOpenedAt: d2)
            return accId
        }
        let extras = try db.summaryExtras(accountId: accountId, personRowId: nil, asOf: Self.asOf)
        #expect(extras.streakDays == 3)
    }

    @Test
    func summaryExtras_streak_breaksOnGap() async throws {
        let db = try AppDatabase.inMemory()
        // Activity on asOf and asOf-2, but NOT asOf-1 → streak = 1 (only asOf)
        let d0 = Self.asOf.addingTimeInterval(12 * 3600)
        let d2 = Self.asOf.addingTimeInterval(-2 * 86400 + 12 * 3600)
        let accountId = try await db.writer.write { db -> Int64 in
            let (accId, _) = try Self.seedAccount(db)
            try Self.insertRead(db, accountId: accId, postServerId: 1, lastOpenedAt: d0)
            try Self.insertRead(db, accountId: accId, postServerId: 3, lastOpenedAt: d2)
            return accId
        }
        let extras = try db.summaryExtras(accountId: accountId, personRowId: nil, asOf: Self.asOf)
        #expect(extras.streakDays == 1)
    }

    @Test
    func summaryExtras_streak_zeroWhenLastActivityBeforeAsOf() async throws {
        let db = try AppDatabase.inMemory()
        // Activity only yesterday (asOf-1 noon), none on asOf → streak = 0
        let yesterday = Self.asOf.addingTimeInterval(-86400 + 12 * 3600)
        let accountId = try await db.writer.write { db -> Int64 in
            let (accId, _) = try Self.seedAccount(db)
            try Self.insertRead(db, accountId: accId, postServerId: 1, lastOpenedAt: yesterday)
            return accId
        }
        let extras = try db.summaryExtras(accountId: accountId, personRowId: nil, asOf: Self.asOf)
        #expect(extras.streakDays == 0)
    }

    @Test
    func summaryExtras_streak_votesCountTowardStreak() async throws {
        let db = try AppDatabase.inMemory()
        let noonOnAsOf = Self.asOf.addingTimeInterval(12 * 3600)
        let accountId = try await db.writer.write { db -> Int64 in
            let (accId, _) = try Self.seedAccount(db)
            // Only a vote on asOf, no reads
            try Self.insertVote(db, accountId: accId, entityServerId: 1, votedAt: noonOnAsOf)
            return accId
        }
        let extras = try db.summaryExtras(accountId: accountId, personRowId: nil, asOf: Self.asOf)
        #expect(extras.streakDays == 1)
    }

    @Test
    func summaryExtras_streak_authoredPostCountsTowardStreak() async throws {
        let db = try AppDatabase.inMemory()
        // An authored post on asOf with no reads or votes that day must produce a streak of 1.
        let noonOnAsOf = Self.asOf.addingTimeInterval(12 * 3600)
        let (accountId, personRowId) = try await db.writer.write { db -> (Int64, Int64) in
            let (accId, siteId) = try Self.seedAccount(db)
            let personId = try Self.seedPerson(db, siteId: siteId)
            let commId = try Self.seedCommunity(db, accountId: accId)
            try Self.insertAuthoredPost(
                db, accountId: accId, communityId: commId,
                creatorId: personId, serverPostId: 1, published: noonOnAsOf
            )
            return (accId, personId)
        }
        let extras = try db.summaryExtras(
            accountId: accountId, personRowId: personRowId, asOf: Self.asOf
        )
        #expect(extras.streakDays == 1)
    }

    // MARK: - summaryExtras — topCommunity

    @Test
    func summaryExtras_topCommunity_nilWhenNoActivity() async throws {
        let db = try AppDatabase.inMemory()
        let accountId = try await db.writer.write { try Self.seedAccount($0).accountId }
        let extras = try db.summaryExtras(accountId: accountId, personRowId: nil, asOf: Self.asOf)
        #expect(extras.topCommunity == nil)
    }

    @Test
    func summaryExtras_topCommunity_returnsNameFromVoteEvents() async throws {
        let db = try AppDatabase.inMemory()
        let t = Self.asOf.addingTimeInterval(12 * 3600)
        let accountId = try await db.writer.write { db -> Int64 in
            let (accId, _) = try Self.seedAccount(db)
            // 3 votes in "swift", 1 vote in "ios"
            try Self.insertVote(db, accountId: accId, entityServerId: 1, votedAt: t, communityName: "swift", communityActorId: "https://t/c/swift")
            try Self.insertVote(db, accountId: accId, entityServerId: 2, votedAt: t, communityName: "swift", communityActorId: "https://t/c/swift")
            try Self.insertVote(db, accountId: accId, entityServerId: 3, votedAt: t, communityName: "swift", communityActorId: "https://t/c/swift")
            try Self.insertVote(db, accountId: accId, entityServerId: 4, votedAt: t, communityName: "ios", communityActorId: "https://t/c/ios")
            return accId
        }
        let extras = try db.summaryExtras(accountId: accountId, personRowId: nil, asOf: Self.asOf)
        #expect(extras.topCommunity == "swift")
    }

    @Test
    func summaryExtras_topCommunity_tieBreaksAlphabetically() async throws {
        let db = try AppDatabase.inMemory()
        let t = Self.asOf.addingTimeInterval(12 * 3600)
        let accountId = try await db.writer.write { db -> Int64 in
            let (accId, _) = try Self.seedAccount(db)
            // Equal vote counts: "apple" and "zebra" → alphabetical → "apple"
            try Self.insertVote(db, accountId: accId, entityServerId: 1, votedAt: t, communityName: "zebra", communityActorId: "https://t/c/zebra")
            try Self.insertVote(db, accountId: accId, entityServerId: 2, votedAt: t, communityName: "apple", communityActorId: "https://t/c/apple")
            return accId
        }
        let extras = try db.summaryExtras(accountId: accountId, personRowId: nil, asOf: Self.asOf)
        #expect(extras.topCommunity == "apple")
    }

    @Test
    func summaryExtras_topCommunity_includesAuthoredPostCommunities() async throws {
        let db = try AppDatabase.inMemory()
        let t = Self.asOf.addingTimeInterval(12 * 3600)
        let (accountId, personRowId) = try await db.writer.write { db -> (Int64, Int64) in
            let (accId, siteId) = try Self.seedAccount(db)
            let personId = try Self.seedPerson(db, siteId: siteId)
            // "rust": 1 vote event; "swift": 2 authored posts → swift wins
            let commSwift = try Self.seedCommunity(db, accountId: accId, serverCommunityId: 1, name: "swift")
            try Self.insertVote(db, accountId: accId, entityServerId: 1, votedAt: t, communityName: "rust", communityActorId: "https://t/c/rust")
            try Self.insertAuthoredPost(db, accountId: accId, communityId: commSwift, creatorId: personId, serverPostId: 10, published: t)
            try Self.insertAuthoredPost(db, accountId: accId, communityId: commSwift, creatorId: personId, serverPostId: 11, published: t.addingTimeInterval(60))
            return (accId, personId)
        }
        let extras = try db.summaryExtras(accountId: accountId, personRowId: personRowId, asOf: Self.asOf)
        #expect(extras.topCommunity == "swift")
    }

    // MARK: - summaryExtras — busiest

    @Test
    func summaryExtras_busiest_nilWhenNoActivity() async throws {
        let db = try AppDatabase.inMemory()
        let accountId = try await db.writer.write { try Self.seedAccount($0).accountId }
        let extras = try db.summaryExtras(accountId: accountId, personRowId: nil, asOf: Self.asOf)
        #expect(extras.busiest == nil)
    }

    @Test
    func summaryExtras_busiest_mornings_reads() async throws {
        let db = try AppDatabase.inMemory()
        // 09:00 UTC = "Mornings" (hour band 5-11)
        let t = Self.asOf.addingTimeInterval(9 * 3600)
        let accountId = try await db.writer.write { db -> Int64 in
            let (accId, _) = try Self.seedAccount(db)
            try Self.insertRead(db, accountId: accId, postServerId: 1, lastOpenedAt: t)
            return accId
        }
        let extras = try db.summaryExtras(accountId: accountId, personRowId: nil, asOf: Self.asOf)
        #expect(extras.busiest == "Mornings")
    }

    @Test
    func summaryExtras_busiest_afternoons_votes() async throws {
        let db = try AppDatabase.inMemory()
        // 14:00 UTC = "Afternoons" (hour band 12-17)
        let t = Self.asOf.addingTimeInterval(14 * 3600)
        let accountId = try await db.writer.write { db -> Int64 in
            let (accId, _) = try Self.seedAccount(db)
            try Self.insertVote(db, accountId: accId, entityServerId: 1, votedAt: t)
            return accId
        }
        let extras = try db.summaryExtras(accountId: accountId, personRowId: nil, asOf: Self.asOf)
        #expect(extras.busiest == "Afternoons")
    }

    @Test
    func summaryExtras_busiest_evenings() async throws {
        let db = try AppDatabase.inMemory()
        // 20:00 UTC = "Evenings" (hour band 18-22)
        let t = Self.asOf.addingTimeInterval(20 * 3600)
        let accountId = try await db.writer.write { db -> Int64 in
            let (accId, _) = try Self.seedAccount(db)
            try Self.insertRead(db, accountId: accId, postServerId: 1, lastOpenedAt: t)
            return accId
        }
        let extras = try db.summaryExtras(accountId: accountId, personRowId: nil, asOf: Self.asOf)
        #expect(extras.busiest == "Evenings")
    }

    @Test
    func summaryExtras_busiest_nights() async throws {
        let db = try AppDatabase.inMemory()
        // 02:00 UTC = "Nights" (hours 0-4 and 23)
        let t = Self.asOf.addingTimeInterval(2 * 3600)
        let accountId = try await db.writer.write { db -> Int64 in
            let (accId, _) = try Self.seedAccount(db)
            try Self.insertRead(db, accountId: accId, postServerId: 1, lastOpenedAt: t)
            return accId
        }
        let extras = try db.summaryExtras(accountId: accountId, personRowId: nil, asOf: Self.asOf)
        #expect(extras.busiest == "Nights")
    }

    @Test
    func summaryExtras_busiest_modalBandWinsOverMinority() async throws {
        let db = try AppDatabase.inMemory()
        let tMorning = Self.asOf.addingTimeInterval(8 * 3600) // 08:00 → Mornings
        let tEvening = Self.asOf.addingTimeInterval(19 * 3600) // 19:00 → Evenings
        let accountId = try await db.writer.write { db -> Int64 in
            let (accId, _) = try Self.seedAccount(db)
            // 3 reads in Mornings, 1 vote in Evenings → modal = Mornings
            try Self.insertRead(db, accountId: accId, postServerId: 1, lastOpenedAt: tMorning)
            try Self.insertRead(db, accountId: accId, postServerId: 2, lastOpenedAt: tMorning.addingTimeInterval(60))
            try Self.insertRead(db, accountId: accId, postServerId: 3, lastOpenedAt: tMorning.addingTimeInterval(120))
            try Self.insertVote(db, accountId: accId, entityServerId: 10, votedAt: tEvening)
            return accId
        }
        let extras = try db.summaryExtras(accountId: accountId, personRowId: nil, asOf: Self.asOf)
        #expect(extras.busiest == "Mornings")
    }

    // MARK: - summaryExtras — account isolation

    @Test
    func summaryExtras_accountIsolation() async throws {
        let db = try AppDatabase.inMemory()
        let noonOnAsOf = Self.asOf.addingTimeInterval(12 * 3600) // 12:00 → Afternoons
        let eveningOnAsOf = Self.asOf.addingTimeInterval(20 * 3600) // 20:00 → Evenings
        let (accA, accB) = try await db.writer.write { db -> (Int64, Int64) in
            let (accIdA, _) = try Self.seedAccount(db, host: "alpha.test")
            let (accIdB, _) = try Self.seedAccount(db, host: "beta.test")
            // Account A: activity at noon ("Afternoons"), community "alpha"
            try Self.insertRead(db, accountId: accIdA, postServerId: 1, lastOpenedAt: noonOnAsOf)
            try Self.insertVote(db, accountId: accIdA, entityServerId: 1, votedAt: noonOnAsOf, communityName: "alpha", communityActorId: "https://a/c/alpha")
            // Account B: activity in evening ("Evenings"), community "beta"
            try Self.insertRead(db, accountId: accIdB, postServerId: 2, lastOpenedAt: eveningOnAsOf)
            try Self.insertVote(db, accountId: accIdB, entityServerId: 2, votedAt: eveningOnAsOf, communityName: "beta", communityActorId: "https://b/c/beta")
            return (accIdA, accIdB)
        }
        let extrasA = try db.summaryExtras(accountId: accA, personRowId: nil, asOf: Self.asOf)
        let extrasB = try db.summaryExtras(accountId: accB, personRowId: nil, asOf: Self.asOf)
        #expect(extrasA.topCommunity == "alpha")
        #expect(extrasB.topCommunity == "beta")
        #expect(extrasA.busiest == "Afternoons")
        #expect(extrasB.busiest == "Evenings")
    }
}
