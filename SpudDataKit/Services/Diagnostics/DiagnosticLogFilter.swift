//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

/// A value type that narrows which `DiagnosticEventRecord` rows are returned by
/// `AppDatabase.recentDiagnosticEvents(_:)`.
///
/// All fields are optional/defaulted so callers only specify what they care about:
///
/// ```swift
/// // Last 50 error-or-above events for the outbox subsystem:
/// let filter = DiagnosticLogFilter(categories: [.outbox], minimumLevel: .error, limit: 50)
/// ```
public struct DiagnosticLogFilter: Sendable, Equatable {
    /// Restricts results to this set of categories.
    /// `nil` means all categories are included.
    public var categories: Set<DiagnosticCategory>?

    /// Only rows whose `level` is at least this severity are returned.
    /// Defaults to `.debug`, which includes everything.
    public var minimumLevel: DiagnosticLevel

    /// Case-insensitive substring matched against the `message`, `event`,
    /// `instance`, and `metadata` columns.  Trimmed before use; `nil` or
    /// an all-whitespace string disables text filtering.
    public var searchText: String?

    /// Maximum number of rows to return, ordered newest-first.  Defaults to 1000.
    public var limit: Int

    /// Creates a new filter.
    ///
    /// - Parameters:
    ///   - categories: Set of categories to include; `nil` includes all.
    ///   - minimumLevel: Minimum severity level; defaults to `.debug` (all events).
    ///   - searchText: Substring to search across message/event/instance/metadata.
    ///   - limit: Row cap, applied after all predicates.  Defaults to 1000.
    public init(
        categories: Set<DiagnosticCategory>? = nil,
        minimumLevel: DiagnosticLevel = .debug,
        searchText: String? = nil,
        limit: Int = 1000
    ) {
        self.categories = categories
        self.minimumLevel = minimumLevel
        self.searchText = searchText
        self.limit = limit
    }
}
