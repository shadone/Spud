//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB

/// Broad category of the subsystem that emitted a diagnostic event.
/// Stored as a raw `String` in the `diagnosticEvent` table so new cases survive app downgrades.
public enum DiagnosticCategory: String, Sendable, CaseIterable, Codable {
    case outbox
    case composerOutbox
    case scheduler
    case site
    case offlineDownload
    case unread
    case spotlight
    case lifecycle
}

/// Severity of a diagnostic event, ordered from least to most severe.
/// Stored as a raw `Int` — raw value encodes the ordinal so `<` is a simple integer compare.
public enum DiagnosticLevel: Int, Sendable, Codable, Comparable {
    case debug = 0
    case info = 1
    case notice = 2
    case error = 3

    public static func < (lhs: DiagnosticLevel, rhs: DiagnosticLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A single structured log entry written into the `diagnosticEvent` SQLite table.
///
/// Fields are stored in their primitive forms (`String`/`Int`/`Double`) so that
/// a row can always be inserted even if the category or level value is not yet
/// known to the current binary — use `categoryEnum`/`levelEnum` to decode them
/// into typed enums after reading.
///
/// The `metadata` column holds an optional JSON-encoded `[String: String]` dictionary.
/// Use `metadataDictionary` for a decoded view; returns `nil` when the column is
/// absent, empty, or contains invalid JSON.
public struct DiagnosticEventRecord: Codable, FetchableRecord, MutablePersistableRecord, Sendable, Equatable {
    public var id: Int64?
    /// Unix timestamp (seconds since epoch) of the event.
    public var timestamp: Double
    /// Raw `DiagnosticCategory` string — use `categoryEnum` for typed access.
    public var category: String
    /// Raw `DiagnosticLevel` integer — use `levelEnum` for typed access.
    public var level: Int
    /// A short machine-readable event identifier, e.g. `"fetchFailed"`.
    public var event: String
    /// Human-readable description of what happened.
    public var message: String
    /// Optional Lemmy instance host (e.g. `lemmy.world`), not a full URL, the event is scoped to.
    public var instance: String?
    /// Optional JSON-encoded `[String: String]` payload. See `metadataDictionary`.
    public var metadata: String?

    public static let databaseTableName = "diagnosticEvent"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    // MARK: - Typed convenience accessors

    /// The `level` field decoded to a `DiagnosticLevel`, or `nil` if the stored
    /// integer does not map to a known case (forward-compat guard).
    public var levelEnum: DiagnosticLevel? {
        DiagnosticLevel(rawValue: level)
    }

    /// The `category` field decoded to a `DiagnosticCategory`, or `nil` if the
    /// stored string does not map to a known case (forward-compat guard).
    public var categoryEnum: DiagnosticCategory? {
        DiagnosticCategory(rawValue: category)
    }

    /// The `metadata` JSON string decoded into a `[String: String]` dictionary.
    /// Returns `nil` when `metadata` is `nil`, empty, or contains malformed JSON.
    public var metadataDictionary: [String: String]? {
        guard let raw = metadata, !raw.isEmpty,
              let data = raw.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode([String: String].self, from: data)
    }
}

// MARK: - Memberwise initialiser (for test convenience)

public extension DiagnosticEventRecord {
    /// Creates a new (unsaved) record. `id` starts as `nil`; it is set by
    /// `didInsert` after the first `insert` into GRDB.
    init(
        timestamp: Double,
        category: String,
        level: Int,
        event: String,
        message: String,
        instance: String? = nil,
        metadata: String? = nil
    ) {
        id = nil
        self.timestamp = timestamp
        self.category = category
        self.level = level
        self.event = event
        self.message = message
        self.instance = instance
        self.metadata = metadata
    }
}
