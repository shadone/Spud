//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit

/// View model for the in-app Event Log viewer.
///
/// Drives a live, filterable list of `DiagnosticEventRecord` rows from GRDB.
/// Reconnects the underlying `ValueObservation` whenever the filter changes so the
/// list always reflects the current predicate without stale rows leaking through.
///
/// Injected via `diagnostics: DiagnosticLogging` and `appDatabase: AppDatabase` so
/// the clear action and the live observation can both be exercised in tests without a
/// running app.
@MainActor
@Observable
final class DiagnosticLogViewModel {
    // MARK: - Filter inputs (mutated by the view)

    /// Category filter. Empty set means all categories are shown.
    var selectedCategories: Set<DiagnosticCategory> = []

    /// Minimum severity level shown. Events below this level are hidden.
    var minimumLevel: DiagnosticLevel = .debug

    /// Free-text search. Empty string disables text filtering.
    var searchText: String = ""

    // MARK: - Outputs

    /// The current list of diagnostic events matching the active filter,
    /// ordered newest-first.
    private(set) var events: [DiagnosticEventRecord] = []

    // MARK: - Private

    @ObservationIgnored private let diagnostics: DiagnosticLogging
    @ObservationIgnored private var observationTask: Task<Void, Never>?
    @ObservationIgnored private var filterWatchTask: Task<Void, Never>?

    // MARK: - Init

    init(diagnostics: DiagnosticLogging) {
        self.diagnostics = diagnostics
    }

    deinit {
        filterWatchTask?.cancel()
        observationTask?.cancel()
    }

    // MARK: - Lifecycle

    /// Starts the live GRDB observation and re-subscribes whenever the filter changes.
    ///
    /// Call once from the view's `.task` modifier. The observation is automatically
    /// cancelled when the task group tears down.
    func startObserving(appDatabase: AppDatabase) {
        // Watch for filter changes and resubscribe to the DB observation each time.
        filterWatchTask = Task { [weak self] in
            guard let self else { return }
            for await _ in ObservationStream.values(of: {
                (self.selectedCategories, self.minimumLevel, self.searchText)
            }) {
                guard !Task.isCancelled else { return }
                subscribeToEvents(appDatabase: appDatabase)
            }
        }
    }

    // MARK: - Actions

    /// Deletes all persisted diagnostic events.
    func clear() async {
        await diagnostics.clear()
    }

    /// Produces a plain-text export of the current `events` list.
    ///
    /// Each line is:
    /// `<ISO8601 timestamp> [<LEVEL>] <category> <event> — <message> [instance]`
    ///
    /// The instance suffix is omitted when nil. Lines are joined with newlines,
    /// newest-first (same order as the displayed list).
    func shareText() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return events.map { event in
            let date = Date(timeIntervalSince1970: event.timestamp)
            let timestamp = formatter.string(from: date)
            let levelLabel = event.levelEnum.map(\.shareLabel) ?? "UNKNOWN"
            var line = "\(timestamp) [\(levelLabel)] \(event.category) \(event.event) — \(event.message)"
            if let instance = event.instance {
                line += " [\(instance)]"
            }
            return line
        }.joined(separator: "\n")
    }

    // MARK: - Private helpers

    private func subscribeToEvents(appDatabase: AppDatabase) {
        observationTask?.cancel()
        let filter = buildFilter()
        observationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await records in appDatabase.observeDiagnosticEvents(filter) {
                if Task.isCancelled { break }
                events = records
            }
        }
    }

    private func buildFilter() -> DiagnosticLogFilter {
        DiagnosticLogFilter(
            categories: selectedCategories.isEmpty ? nil : selectedCategories,
            minimumLevel: minimumLevel,
            searchText: searchText.isEmpty ? nil : searchText,
            limit: 500
        )
    }
}

// MARK: - Private helpers

private extension DiagnosticLevel {
    /// Short uppercase label used in the share text export.
    var shareLabel: String {
        switch self {
        case .debug: "DEBUG"
        case .info: "INFO"
        case .notice: "NOTICE"
        case .error: "ERROR"
        }
    }
}
