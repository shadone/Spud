//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import OSLog

// MARK: - Has protocol

/// Dependency-injection accessor for the shared diagnostic recorder.
public protocol HasDiagnosticLog {
    var diagnosticLog: DiagnosticLogging { get }
}

// MARK: - Protocol

/// A dual-sink diagnostic recorder: every event is emitted to OSLog **and** persisted
/// to the `diagnosticEvent` GRDB table for later retrieval in the in-app log viewer.
///
/// Conformances must be `Sendable` so a single recorder can be shared across actors
/// (e.g. injected into `OutboxService`, `SchedulerService`, etc.).
public protocol DiagnosticLogging: Sendable {
    /// Records a structured diagnostic event.
    ///
    /// Implementations must be best-effort: a failure to persist MUST NOT propagate
    /// as a thrown error to the caller, and MUST NOT crash a service drain.
    ///
    /// - Parameters:
    ///   - category: Broad subsystem bucket (e.g. `.outbox`, `.scheduler`).
    ///   - level: Severity of the event.
    ///   - event: Short machine-readable identifier, e.g. `"op.permanentRollback"`.
    ///   - message: Human-readable description of what happened.
    ///   - instance: Optional Lemmy actor-ID URL (`https://lemmy.world`) the event is
    ///     scoped to.
    ///   - metadata: Optional key-value pairs providing structured context (e.g. HTTP
    ///     status, operation kind).
    func record(
        category: DiagnosticCategory,
        level: DiagnosticLevel,
        event: String,
        message: String,
        instance: String?,
        metadata: [String: String]?
    ) async

    /// Returns recent diagnostic events matching `filter`, ordered newest-first.
    func recent(_ filter: DiagnosticLogFilter) async -> [DiagnosticEventRecord]

    /// Deletes all persisted diagnostic events.
    func clear() async
}

// MARK: - Production implementation

/// A `DiagnosticLogging` implementation that fans each event to:
/// 1. **OSLog** — using the category's dedicated `Logger` at the mapped `OSLogType`.
/// 2. **GRDB** (`diagnosticEvent` table) — via `AppDatabase.insertDiagnosticEvent(_:)`,
///    best-effort (`try?` so a DB error never propagates to callers).
///
/// Inject `now` in tests to produce deterministic timestamps without real-clock
/// dependencies.
public struct DiagnosticLog: DiagnosticLogging {
    // MARK: - Dependencies

    /// The database used for persistence.
    public let appDatabase: AppDatabase

    /// Clock source returning Unix timestamp (seconds since epoch).
    /// Defaults to `Date().timeIntervalSince1970`.  Injectable for tests.
    public let now: @Sendable () -> Double

    // MARK: - Init

    /// Creates a `DiagnosticLog`.
    ///
    /// - Parameters:
    ///   - appDatabase: Database to persist events into.
    ///   - now: Clock source; defaults to wall-clock time.
    public init(
        appDatabase: AppDatabase,
        now: @Sendable @escaping () -> Double = { Date().timeIntervalSince1970 }
    ) {
        self.appDatabase = appDatabase
        self.now = now
    }

    // MARK: - DiagnosticLogging

    public func record(
        category: DiagnosticCategory,
        level: DiagnosticLevel,
        event: String,
        message: String,
        instance: String?,
        metadata: [String: String]?
    ) async {
        // Emit to OSLog first (synchronous, infallible).
        let osLogger = logger(for: category)
        let osType = osLogType(for: level)
        // OSLog requires a string literal for the format — use the interpolated
        // form so the structured fields appear in Console.app.
        let instanceDesc = instance.map { " [\($0)]" } ?? ""
        let metaDesc = metadata.map { " \($0)" } ?? ""
        osLogger.log(level: osType, "\(event, privacy: .public)\(instanceDesc, privacy: .public): \(message, privacy: .public)\(metaDesc, privacy: .public)")

        // Encode metadata as a JSON string for storage.
        var metadataString: String?
        if let dict = metadata,
           let data = try? JSONEncoder().encode(dict),
           let str = String(bytes: data, encoding: .utf8)
        {
            metadataString = str
        }

        let record = DiagnosticEventRecord(
            timestamp: now(),
            category: category.rawValue,
            level: level.rawValue,
            event: event,
            message: message,
            instance: instance,
            metadata: metadataString
        )

        // Best-effort persistence — a DB failure must never crash a service drain.
        try? await appDatabase.insertDiagnosticEvent(record)
    }

    public func recent(_ filter: DiagnosticLogFilter) async -> [DiagnosticEventRecord] {
        await (try? appDatabase.recentDiagnosticEvents(filter)) ?? []
    }

    public func clear() async {
        try? await appDatabase.clearDiagnosticEvents()
    }

    // MARK: - Pure mapping helpers (testable without I/O)

    /// Maps a `DiagnosticLevel` to its corresponding `OSLogType`.
    ///
    /// | `DiagnosticLevel` | `OSLogType`  |
    /// |---|---|
    /// | `.debug`  | `.debug`   |
    /// | `.info`   | `.info`    |
    /// | `.notice` | `.default` |
    /// | `.error`  | `.error`   |
    public func osLogType(for level: DiagnosticLevel) -> OSLogType {
        switch level {
        case .debug: .debug
        case .info: .info
        case .notice: .default
        case .error: .error
        }
    }

    /// Returns the SpudDataKit `Logger` that best represents `category`.
    ///
    /// Category-to-Logger mapping:
    /// - `.outbox` → `Logger.outbox`
    /// - `.composerOutbox` → `Logger.composerOutbox`
    /// - `.scheduler` → `Logger.schedulerService`
    /// - `.site` → `Logger.lemmyService`
    /// - `.offlineDownload` → `Logger.offlineDownloadService`
    /// - `.unread` → `Logger.inbox`
    /// - `.spotlight` → `Logger.spotlight` (added to Logger.swift for this feature)
    /// - `.lifecycle` → `Logger.lifecycle` (added to Logger.swift for this feature)
    public func logger(for category: DiagnosticCategory) -> Logger {
        switch category {
        case .outbox: Logger.outbox
        case .composerOutbox: Logger.composerOutbox
        case .scheduler: Logger.schedulerService
        case .site: Logger.lemmyService
        case .offlineDownload: Logger.offlineDownloadService
        case .unread: Logger.inbox
        case .spotlight: Logger.spotlight
        case .lifecycle: Logger.lifecycle
        }
    }
}
