//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudDataKit

// MARK: - DiagnosticLog integration tests

struct DiagnosticLogTests {
    // MARK: - record + recent round-trip

    @Test
    func record_storesEventAndReturnsOnQuery() async throws {
        let db = try AppDatabase.inMemory()
        // Use a fixed constant — Swift 6 doesn't allow capturing mutable vars
        // in @Sendable closures. A constant timestamp is sufficient for this test.
        let fixedTime = 1_000_000.0
        let log = DiagnosticLog(appDatabase: db, now: { fixedTime })

        await log.record(
            category: .outbox,
            level: .error,
            event: "op.permanentRollback",
            message: "x",
            instance: "lemmy.world",
            metadata: ["httpStatus": "403"]
        )

        let rows = await log.recent(DiagnosticLogFilter(categories: [.outbox]))
        #expect(rows.count == 1)

        let row = try #require(rows.first)
        #expect(row.event == "op.permanentRollback")
        #expect(row.categoryEnum == .outbox)
        #expect(row.levelEnum == .error)
        #expect(row.instance == "lemmy.world")
        #expect(row.metadataDictionary?["httpStatus"] == "403")
    }

    @Test
    func record_multipleCategories_filterIsHonored() async throws {
        let db = try AppDatabase.inMemory()
        let log = DiagnosticLog(appDatabase: db)

        await log.record(category: .outbox, level: .info, event: "a", message: "a", instance: nil, metadata: nil)
        await log.record(category: .scheduler, level: .info, event: "b", message: "b", instance: nil, metadata: nil)

        let outboxRows = await log.recent(DiagnosticLogFilter(categories: [.outbox]))
        #expect(outboxRows.count == 1)
        #expect(outboxRows[0].event == "a")

        let schedulerRows = await log.recent(DiagnosticLogFilter(categories: [.scheduler]))
        #expect(schedulerRows.count == 1)
        #expect(schedulerRows[0].event == "b")
    }

    @Test
    func clear_removesAllEvents() async throws {
        let db = try AppDatabase.inMemory()
        let log = DiagnosticLog(appDatabase: db)

        await log.record(category: .outbox, level: .debug, event: "e1", message: "m", instance: nil, metadata: nil)
        await log.clear()

        let rows = await log.recent(DiagnosticLogFilter())
        // swiftformat:disable:next isEmpty
        #expect(rows.count == 0)
    }

    // MARK: - osLogType mapping

    @Test
    func osLogType_mapsAllLevelsCorrectly() throws {
        let db = try AppDatabase.inMemory()
        let log = DiagnosticLog(appDatabase: db)
        #expect(log.osLogType(for: .debug) == .debug)
        #expect(log.osLogType(for: .info) == .info)
        #expect(log.osLogType(for: .notice) == .default)
        #expect(log.osLogType(for: .error) == .error)
    }

    // MARK: - metadata encoding

    @Test
    func record_nilMetadata_storesNilMetadataColumn() async throws {
        let db = try AppDatabase.inMemory()
        let log = DiagnosticLog(appDatabase: db)

        await log.record(category: .site, level: .debug, event: "ping", message: "ok", instance: nil, metadata: nil)

        let rows = await log.recent(DiagnosticLogFilter(categories: [.site]))
        #expect(rows.count == 1)
        #expect(rows[0].metadata == nil)
    }
}

// MARK: - DiagnosticLogSpy tests

struct DiagnosticLogSpyTests {
    @Test
    func spy_capturesRecord() async {
        let spy = DiagnosticLogSpy()

        await spy.record(
            category: .composerOutbox,
            level: .notice,
            event: "submit.queued",
            message: "Comment queued",
            instance: "beehaw.org",
            metadata: ["commentId": "42"]
        )

        let captured = spy.recordedEvents
        #expect(captured.count == 1)
        #expect(captured[0].category == .composerOutbox)
        #expect(captured[0].level == .notice)
        #expect(captured[0].event == "submit.queued")
        #expect(captured[0].message == "Comment queued")
        #expect(captured[0].instance == "beehaw.org")
        #expect(captured[0].metadata == ["commentId": "42"])
    }

    @Test
    func spy_eventsMatchingEvent_filtersCorrectly() async {
        let spy = DiagnosticLogSpy()

        await spy.record(category: .outbox, level: .info, event: "enqueued", message: "a", instance: nil, metadata: nil)
        await spy.record(category: .outbox, level: .error, event: "permanentFail", message: "b", instance: nil, metadata: nil)
        await spy.record(category: .scheduler, level: .info, event: "enqueued", message: "c", instance: nil, metadata: nil)

        let matched = spy.events(matching: "enqueued")
        #expect(matched.count == 2)
    }

    @Test
    func spy_recent_returnsRecordedEventsAsFakeRows() async {
        let spy = DiagnosticLogSpy()
        await spy.record(category: .outbox, level: .debug, event: "x", message: "y", instance: nil, metadata: nil)

        let rows = await spy.recent(DiagnosticLogFilter())
        #expect(rows.count == 1)
        #expect(rows[0].event == "x")
    }

    @Test
    func spy_clear_removesAllCapturedEvents() async {
        let spy = DiagnosticLogSpy()
        await spy.record(category: .outbox, level: .info, event: "e", message: "m", instance: nil, metadata: nil)
        await spy.clear()
        let rows = await spy.recent(DiagnosticLogFilter())
        // swiftformat:disable:next isEmpty
        #expect(rows.count == 0)
        // swiftformat:disable:next isEmpty
        #expect(spy.recordedEvents.count == 0)
    }
}
