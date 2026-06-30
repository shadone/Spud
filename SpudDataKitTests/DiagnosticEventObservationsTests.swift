//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import Testing
@testable import SpudDataKit

/// Coverage for `AppDatabase.observeDiagnosticEvents(_:)` — the live
/// `ValueObservation`-backed stream of filtered diagnostic events.
struct DiagnosticEventObservationsTests {
    // MARK: - Helpers

    private static func makeEvent(
        timestamp: Double = 1_000_000,
        category: DiagnosticCategory = .outbox,
        level: DiagnosticLevel = .info,
        event: String = "testEvent",
        message: String = "test message"
    ) -> DiagnosticEventRecord {
        DiagnosticEventRecord(
            timestamp: timestamp,
            category: category.rawValue,
            level: level.rawValue,
            event: event,
            message: message
        )
    }

    // MARK: - Tests

    /// Verifies the stream emits an initial value immediately after subscription
    /// (the GRDB ValueObservation contract) and then re-emits when a new event is
    /// inserted that matches the filter.
    @Test
    func yieldsInitialEmptyThenUpdatesOnInsert() async throws {
        let db = try AppDatabase.inMemory()
        let stream = db.observeDiagnosticEvents(DiagnosticLogFilter())

        var iterator = stream.makeAsyncIterator()

        // First emission: table is empty.
        let initial = await iterator.next()
        // swiftformat:disable:next isEmpty
        #expect(initial?.count == 0)

        // Insert an event; the observation must fire again.
        try await db.insertDiagnosticEvent(Self.makeEvent(message: "hello from observation"))

        // Poll until the inserted event lands in a yield.
        var matched = false
        for await batch in stream {
            if batch.contains(where: { $0.message == "hello from observation" }) {
                matched = true
                break
            }
        }
        #expect(matched)
    }

    /// Verifies that the `minimumLevel` filter is applied live: events below the
    /// threshold do not trigger a non-empty yield.
    @Test
    func levelFilter_suppressesBelowThreshold() async throws {
        let db = try AppDatabase.inMemory()
        let filter = DiagnosticLogFilter(minimumLevel: .error)
        var iterator = db.observeDiagnosticEvents(filter).makeAsyncIterator()

        // Consume the initial (empty) emission.
        _ = await iterator.next()

        // Insert a debug event — must NOT surface through the error filter.
        try await db.insertDiagnosticEvent(Self.makeEvent(level: .debug, message: "low priority"))
        // Insert an error event — MUST surface.
        try await db.insertDiagnosticEvent(Self.makeEvent(level: .error, message: "critical failure"))

        // Wait for the batch that contains an error-level event.
        var matched = false
        while let batch = await iterator.next() {
            if batch.contains(where: { $0.levelEnum == .error }) {
                // Debug event must not be in the result — level filter is active.
                #expect(batch.allSatisfy { $0.levelEnum == .error })
                matched = true
                break
            }
        }
        #expect(matched)
    }

    /// Verifies that the `categories` filter restricts live results to the
    /// specified category set.
    @Test
    func categoryFilter_restrictsToMatchingCategory() async throws {
        let db = try AppDatabase.inMemory()
        let filter = DiagnosticLogFilter(categories: [.scheduler])
        var iterator = db.observeDiagnosticEvents(filter).makeAsyncIterator()

        // Consume the initial (empty) emission.
        _ = await iterator.next()

        // Insert an outbox event — must not surface in the scheduler filter.
        try await db.insertDiagnosticEvent(Self.makeEvent(category: .outbox, message: "outbox msg"))
        // Insert a scheduler event — must surface.
        try await db.insertDiagnosticEvent(Self.makeEvent(category: .scheduler, message: "scheduler msg"))

        // Wait for the batch that contains the scheduler event.
        var matched = false
        while let batch = await iterator.next() {
            if batch.contains(where: { $0.categoryEnum == .scheduler }) {
                // Must not leak the outbox event.
                #expect(batch.allSatisfy { $0.categoryEnum == .scheduler })
                matched = true
                break
            }
        }
        #expect(matched)
    }

    /// Verifies that `searchText` filtering works live: only events whose
    /// message/event/instance/metadata contains the search term are yielded.
    @Test
    func searchText_filtersMatchingEvents() async throws {
        let db = try AppDatabase.inMemory()
        let filter = DiagnosticLogFilter(searchText: "needle")
        var iterator = db.observeDiagnosticEvents(filter).makeAsyncIterator()

        // Consume the initial empty emission.
        _ = await iterator.next()

        // Insert an event that does NOT match.
        try await db.insertDiagnosticEvent(Self.makeEvent(message: "hay"))
        // Insert an event that DOES match.
        try await db.insertDiagnosticEvent(Self.makeEvent(message: "needle in a haystack"))

        var matched = false
        while let batch = await iterator.next() {
            if batch.contains(where: { $0.message.contains("needle") }) {
                #expect(batch.allSatisfy { $0.message.contains("needle") })
                matched = true
                break
            }
        }
        #expect(matched)
    }

    /// Verifies the `limit` parameter is honoured: the stream never yields more
    /// rows than the configured cap.
    @Test
    func limit_capsResultCount() async throws {
        let db = try AppDatabase.inMemory()
        let filter = DiagnosticLogFilter(limit: 2)
        var iterator = db.observeDiagnosticEvents(filter).makeAsyncIterator()

        _ = await iterator.next() // initial empty emission

        // Insert 3 events.
        for i in 0..<3 {
            try await db.insertDiagnosticEvent(Self.makeEvent(timestamp: Double(1_000_000 + i), message: "msg \(i)"))
        }

        // Wait until the batch has at least 2 rows, then assert the cap.
        var limitRespected = false
        while let batch = await iterator.next() {
            if batch.count >= 2 {
                #expect(batch.count <= 2)
                limitRespected = true
                break
            }
        }
        #expect(limitRespected)
    }

    /// Verifies the newest-first ordering contract: the stream yields rows
    /// ordered by `timestamp DESC, id DESC`.
    @Test
    func ordering_newestFirst() async throws {
        let db = try AppDatabase.inMemory()
        let stream = db.observeDiagnosticEvents(DiagnosticLogFilter())
        var iterator = stream.makeAsyncIterator()

        _ = await iterator.next() // initial empty

        // Insert three events with distinct timestamps.
        try await db.insertDiagnosticEvent(Self.makeEvent(timestamp: 1000, message: "oldest"))
        try await db.insertDiagnosticEvent(Self.makeEvent(timestamp: 3000, message: "newest"))
        try await db.insertDiagnosticEvent(Self.makeEvent(timestamp: 2000, message: "middle"))

        // Poll until all three land.
        var sorted = false
        while let batch = await iterator.next() {
            guard batch.count == 3 else { continue }
            #expect(batch[0].timestamp >= batch[1].timestamp)
            #expect(batch[1].timestamp >= batch[2].timestamp)
            sorted = true
            break
        }
        #expect(sorted)
    }
}
