//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import OSLog
import SwiftUI

/// Settings → About → Logs → System Log tab.
///
/// Reads OSLog entries for the current process via `OSLogStore` and presents them
/// in a filterable, non-editable text view with copy and share actions.
///
/// Fixes compared to the previous `PreferencesLogsView`:
/// - Entries are separated by newlines (the old `+=` produced a single blob).
/// - Each entry shows its severity level alongside category and timestamp.
/// - A level filter and a category filter let the user narrow what is shown.
/// - A time-window picker replaces the hard-coded 1-hour window.
/// - `OSLogStore` errors surface inline instead of silently producing a blank view.
/// - Text is read-only (`TextEditor` replaced with a `ScrollView` + `Text`).
struct SystemLogView: View {
    // MARK: - State

    @State private var entries: [SystemLogEntry] = []
    @State private var errorMessage: String?
    @State private var isLoading = false

    // MARK: - Filter state

    @State private var selectedWindow: TimeWindow = .lastHour
    @State private var selectedLevel: SystemLogLevel = .all
    @State private var selectedCategory: String = SystemLogView.allCategoriesToken

    // MARK: - Private

    private static let allCategoriesToken = "All"

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            content
        }
        .navigationTitle("System Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarItems }
        .task(id: filterKey) {
            await reload()
        }
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                windowPicker
                levelPicker
                categoryPicker
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private var windowPicker: some View {
        Picker("Time window", selection: $selectedWindow) {
            ForEach(TimeWindow.allCases) { window in
                Text(window.label).tag(window)
            }
        }
        .pickerStyle(.menu)
        .accessibilityLabel("Time window")
    }

    private var levelPicker: some View {
        Picker("Level", selection: $selectedLevel) {
            ForEach(SystemLogLevel.allCases) { level in
                Text(level.label).tag(level)
            }
        }
        .pickerStyle(.menu)
        .accessibilityLabel("Minimum severity level")
    }

    private var categoryPicker: some View {
        Picker("Category", selection: $selectedCategory) {
            Text("All categories").tag(SystemLogView.allCategoriesToken)
            ForEach(availableCategories, id: \.self) { cat in
                Text(cat).tag(cat)
            }
        }
        .pickerStyle(.menu)
        .accessibilityLabel("Category filter")
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            errorView(message: errorMessage)
        } else if filteredEntries.isEmpty {
            Text("No log entries")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("No log entries for current filter")
        } else {
            logTextView
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Could not read OSLog store")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error reading system log: \(message)")
    }

    private var logTextView: some View {
        ScrollView {
            Text(formattedText)
                // Monospaced so timestamps and levels line up.
                .font(.system(.caption2, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            ShareLink(
                item: formattedText,
                subject: Text("Spud System Log"),
                message: Text("OSLog export")
            )
            .accessibilityLabel("Share system log")
        }
    }

    // MARK: - Derived

    /// A string that changes whenever any filter changes, used as the `.task(id:)` key.
    private var filterKey: String {
        "\(selectedWindow.rawValue)-\(selectedLevel.rawValue)-\(selectedCategory)"
    }

    /// Returns the distinct OSLog categories found in the loaded entries.
    private var availableCategories: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for entry in entries where !entry.category.isEmpty {
            if seen.insert(entry.category).inserted {
                result.append(entry.category)
            }
        }
        return result.sorted()
    }

    /// Entries filtered by the current level and category selections.
    private var filteredEntries: [SystemLogEntry] {
        entries.filter { entry in
            let passesLevel = entry.level >= selectedLevel.minimumOSLevel
            let passesCategory =
                selectedCategory == SystemLogView.allCategoriesToken ||
                entry.category == selectedCategory
            return passesLevel && passesCategory
        }
    }

    /// Plain-text export of all `filteredEntries`, one entry per line.
    private var formattedText: String {
        filteredEntries.map(\.formattedLine).joined(separator: "\n")
    }

    // MARK: - Load

    @MainActor
    private func reload() async {
        isLoading = true
        errorMessage = nil

        // Capture before the detached task to satisfy strict-concurrency
        // (MainActor-isolated `selectedWindow` cannot be read from a non-isolated closure).
        let window = selectedWindow

        // Run the OSLogStore read on a background thread; it can be slow.
        let result = await Task.detached(priority: .userInitiated) {
            SystemLogView.readEntries(window: window)
        }.value

        switch result {
        case let .success(loaded):
            entries = loaded
            errorMessage = nil
        case let .failure(err):
            entries = []
            errorMessage = err.localizedDescription
        }

        isLoading = false
    }

    /// Reads `OSLogStore` entries for the current process, bounded by `window`.
    ///
    /// Marked `nonisolated` so it can be called from a `Task.detached` closure
    /// (SwiftUI `View` bodies are implicitly `@MainActor`; static methods inherit that
    /// isolation). It returns a `Result` so the caller decides how to surface failures —
    /// previous code swallowed them, yielding a blank screen.
    private nonisolated static func readEntries(window: TimeWindow) -> Result<[SystemLogEntry], Error> {
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let bundleId = Bundle.main.bundleIdentifier ?? ""
            let startDate = window.startDate
            let position = store.position(date: startDate)

            let raw = try store
                .getEntries(at: position)
                .compactMap { $0 as? OSLogEntryLog }
                .filter { $0.subsystem == bundleId }

            let entries = raw.map { entry in
                SystemLogEntry(
                    date: entry.date,
                    level: entry.level,
                    category: entry.category,
                    message: entry.composedMessage
                )
            }
            return .success(entries)
        } catch {
            return .failure(error)
        }
    }
}

// MARK: - Supporting types

/// A single OSLog entry surfaced by `SystemLogView`.
private struct SystemLogEntry {
    let date: Date
    let level: OSLogEntryLog.Level
    let category: String
    let message: String

    /// One-line representation for the plain-text export and display.
    ///
    /// Format: `<timestamp> [<LEVEL>] [<category>] <message>`
    var formattedLine: String {
        let ts = date.formatted(date: .numeric, time: .standard)
        return "\(ts) [\(levelLabel)] [\(category)] \(message)"
    }

    private var levelLabel: String {
        switch level {
        case .undefined: "---"
        case .debug: "DEBUG"
        case .info: "INFO"
        case .notice: "NOTICE"
        case .error: "ERROR"
        case .fault: "FAULT"
        @unknown default: "???"
        }
    }
}

// MARK: - Time window

/// Selectable time windows for the OSLog query.
private enum TimeWindow: String, CaseIterable, Identifiable {
    case lastHour
    case last24Hours
    case sinceLaunch

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .lastHour: "Last hour"
        case .last24Hours: "Last 24h"
        case .sinceLaunch: "Since launch"
        }
    }

    /// Start date for the `OSLogStore.position(date:)` call.
    var startDate: Date {
        switch self {
        case .lastHour:
            return Date.now.addingTimeInterval(-3600)
        case .last24Hours:
            return Date.now.addingTimeInterval(-86400)
        case .sinceLaunch:
            // Use the process start time if available, otherwise fall back to
            // a generous 7-day window (OSLog truncates to what it has anyway).
            if let processStartTime = ProcessInfo.processInfo.systemUptime as Double? {
                return Date.now.addingTimeInterval(-processStartTime)
            }
            return Date.now.addingTimeInterval(-7 * 86400)
        }
    }
}

// MARK: - Level filter

/// Selectable severity-level filter.
///
/// `all` shows every entry; others set a floor — the view hides anything below the
/// chosen level. Level comparison uses `OSLogEntryLog.Level`'s raw value ordering:
/// undefined(0) < debug(1) < info(2) < notice(3) < error(4) < fault(5).
private enum SystemLogLevel: String, CaseIterable, Identifiable {
    case all
    case debug
    case info
    case notice
    case error

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .all: "All levels"
        case .debug: "Debug+"
        case .info: "Info+"
        case .notice: "Notice+"
        case .error: "Error+"
        }
    }

    /// The minimum `OSLogEntryLog.Level` that passes the filter.
    var minimumOSLevel: OSLogEntryLog.Level {
        switch self {
        case .all: .undefined
        case .debug: .debug
        case .info: .info
        case .notice: .notice
        case .error: .error
        }
    }
}

// MARK: - Comparable conformance for OSLogEntryLog.Level

extension OSLogEntryLog.Level: Comparable {
    public static func < (lhs: OSLogEntryLog.Level, rhs: OSLogEntryLog.Level) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
