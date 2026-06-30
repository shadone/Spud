//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import os
@testable import SpudDataKit

/// A test double for `DiagnosticLogging` that captures every `record(...)` call
/// in memory instead of writing to OSLog or a database.
///
/// Thread-safe: an `OSAllocatedUnfairLock` guards the recorded-events array, so
/// the spy is safe to use across concurrent tasks in Swift Testing suites.
///
/// Reuse this spy in any `SpudDataKitTests` test that needs to assert which
/// diagnostic events a service emitted, without incurring database I/O.
final class DiagnosticLogSpy: DiagnosticLogging, @unchecked Sendable {
    // MARK: - Captured event

    /// A single captured call to `record(...)`.
    struct Recorded {
        let category: DiagnosticCategory
        let level: DiagnosticLevel
        let event: String
        let message: String
        let instance: String?
        let metadata: [String: String]?
    }

    // MARK: - State

    private let lock = OSAllocatedUnfairLock(initialState: [Recorded]())

    /// All events recorded since the spy was created (or since the last `clear()`).
    var recordedEvents: [Recorded] {
        lock.withLock { $0 }
    }

    // MARK: - DiagnosticLogging

    func record(
        category: DiagnosticCategory,
        level: DiagnosticLevel,
        event: String,
        message: String,
        instance: String?,
        metadata: [String: String]?
    ) async {
        let captured = Recorded(
            category: category,
            level: level,
            event: event,
            message: message,
            instance: instance,
            metadata: metadata
        )
        lock.withLock { $0.append(captured) }
    }

    /// Returns fake `DiagnosticEventRecord` rows synthesized from the in-memory log,
    /// applying the same category and level filters as `DiagnosticLogFilter`.
    ///
    /// This is intentionally minimal — it satisfies the protocol contract for tests
    /// that call `recent(_:)` but does not replicate full SQL query semantics.
    func recent(_ filter: DiagnosticLogFilter) async -> [DiagnosticEventRecord] {
        lock.withLock { events in
            events
                .filter { recorded in
                    if let cats = filter.categories, !cats.contains(recorded.category) { return false }
                    return recorded.level >= filter.minimumLevel
                }
                .prefix(filter.limit)
                .map { recorded in
                    var metadataString: String?
                    if let dict = recorded.metadata,
                       let data = try? JSONEncoder().encode(dict),
                       let str = String(bytes: data, encoding: .utf8)
                    {
                        metadataString = str
                    }
                    return DiagnosticEventRecord(
                        timestamp: Date().timeIntervalSince1970,
                        category: recorded.category.rawValue,
                        level: recorded.level.rawValue,
                        event: recorded.event,
                        message: recorded.message,
                        instance: recorded.instance,
                        metadata: metadataString
                    )
                }
        }
    }

    /// Clears all captured events.
    func clear() async {
        lock.withLock { $0.removeAll() }
    }

    // MARK: - Test helpers

    /// Returns all captured events whose `event` string matches `event` exactly.
    func events(matching event: String) -> [Recorded] {
        lock.withLock { $0.filter { $0.event == event } }
    }
}
