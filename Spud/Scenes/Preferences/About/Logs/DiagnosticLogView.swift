//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit
import SwiftUI

/// Settings → About → Logs (new structured view).
///
/// Replaces the raw `OSLogStore` text dump with a filterable, searchable list of
/// `DiagnosticEventRecord` rows drawn live from GRDB. The toolbar offers a share
/// export and a confirmed clear action.
struct DiagnosticLogView: View {
    @State private var viewModel: DiagnosticLogViewModel
    @State private var showClearConfirmation = false
    @State private var selectedEvent: IdentifiableEvent?

    let appDatabase: AppDatabase

    init(diagnostics: DiagnosticLogging, appDatabase: AppDatabase) {
        _viewModel = State(initialValue: DiagnosticLogViewModel(diagnostics: diagnostics))
        self.appDatabase = appDatabase
    }

    var body: some View {
        List {
            filterSection
            if viewModel.events.isEmpty {
                emptyStateSection
            } else {
                eventsSection
            }
        }
        .listStyle(.plain)
        .searchable(text: $viewModel.searchText, prompt: "Search events")
        .navigationTitle("Event Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                ShareLink(
                    item: viewModel.shareText(),
                    subject: Text("Spud Event Log"),
                    message: Text("Diagnostic event log export")
                )
                .accessibilityLabel("Share event log")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(role: .destructive) {
                    showClearConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Clear all events")
            }
        }
        .confirmationDialog(
            "Clear all diagnostic events?",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) {
                Task { await viewModel.clear() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This cannot be undone.")
        }
        .sheet(item: $selectedEvent) { wrapper in
            NavigationStack {
                DiagnosticLogDetailView(event: wrapper.record)
            }
        }
        .task {
            viewModel.startObserving(appDatabase: appDatabase)
        }
    }

    // MARK: - Filter section

    private var filterSection: some View {
        Section {
            levelPicker
            categoryChips
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .listSectionSeparator(.hidden)
    }

    private var levelPicker: some View {
        Picker("Minimum Level", selection: $viewModel.minimumLevel) {
            ForEach(DiagnosticLevel.allPickerCases, id: \.self) { level in
                Text(level.displayLabel).tag(level)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Minimum severity level")
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                CategoryChip(
                    title: "All",
                    isSelected: viewModel.selectedCategories.isEmpty
                ) {
                    viewModel.selectedCategories = []
                }
                ForEach(DiagnosticCategory.allCases, id: \.self) { category in
                    CategoryChip(
                        title: category.displayLabel,
                        isSelected: viewModel.selectedCategories.contains(category)
                    ) {
                        if viewModel.selectedCategories.contains(category) {
                            viewModel.selectedCategories.remove(category)
                        } else {
                            viewModel.selectedCategories.insert(category)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Events section

    private var eventsSection: some View {
        Section {
            ForEach(viewModel.events.map(IdentifiableEvent.init), id: \.id) { wrapper in
                Button {
                    selectedEvent = wrapper
                } label: {
                    DiagnosticLogRowView(event: wrapper.record)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Empty state

    private var emptyStateSection: some View {
        Section {
            Text("No events")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowBackground(Color.clear)
                .accessibilityLabel("No diagnostic events")
        }
    }
}

// MARK: - Category chip

private struct CategoryChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    isSelected
                        ? Color.accentColor.opacity(0.2)
                        : Color(UIColor.secondarySystemFill)
                )
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                .clipShape(Capsule())
        }
        .accessibilityLabel(title)
        .accessibilityHint("Toggles this filter")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Row view

/// A single row in the event log list: level indicator, event name, message,
/// instance tag, and relative timestamp.
struct DiagnosticLogRowView: View {
    let event: DiagnosticEventRecord

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    private var relativeTimestamp: String {
        let date = Date(timeIntervalSince1970: event.timestamp)
        return Self.relativeDateFormatter.localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Level indicator dot
            Circle()
                .fill(levelColor)
                .frame(width: 10, height: 10)
                .padding(.top, 4)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(event.event)
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(relativeTimestamp)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(event.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(levelLabel)
                        .font(.caption2)
                        .foregroundStyle(levelColor)
                    Text(event.category)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let instance = event.instance {
                        Text(instance)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var levelColor: Color {
        switch event.levelEnum {
        case .debug: .secondary
        case .info: .blue
        case .notice: .orange
        case .error: .red
        case nil: .secondary
        }
    }

    private var levelLabel: String {
        switch event.levelEnum {
        case .debug: "DEBUG"
        case .info: "INFO"
        case .notice: "NOTICE"
        case .error: "ERROR"
        case nil: "UNKNOWN"
        }
    }

    private var accessibilityLabel: String {
        var parts = [levelLabel, event.category, event.event, event.message]
        if let instance = event.instance {
            parts.append(instance)
        }
        parts.append(relativeTimestamp)
        return parts.joined(separator: ", ")
    }
}

// MARK: - Detail view

/// Full-detail sheet for a single `DiagnosticEventRecord`.
struct DiagnosticLogDetailView: View {
    let event: DiagnosticEventRecord

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Timestamp") {
                Text(formattedTimestamp)
                    .font(.body)
                    .textSelection(.enabled)
            }
            Section("Level") {
                Text(levelLabel)
                    .font(.body)
                    .textSelection(.enabled)
            }
            Section("Category") {
                Text(event.category)
                    .font(.body)
            }
            if let instance = event.instance {
                Section("Instance") {
                    Text(instance)
                        .font(.body)
                        .textSelection(.enabled)
                }
            }
            Section("Event") {
                Text(event.event)
                    .font(.body)
                    .textSelection(.enabled)
            }
            Section("Message") {
                Text(event.message)
                    .font(.body)
                    .textSelection(.enabled)
            }
            if let dict = event.metadataDictionary, !dict.isEmpty {
                Section("Metadata") {
                    ForEach(dict.keys.sorted(), id: \.self) { key in
                        HStack {
                            Text(key)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(dict[key] ?? "")
                                .textSelection(.enabled)
                        }
                        .font(.body)
                    }
                }
            }
        }
        .navigationTitle("Event Detail")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }

    private var formattedTimestamp: String {
        let date = Date(timeIntervalSince1970: event.timestamp)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private var levelLabel: String {
        switch event.levelEnum {
        case .debug: "Debug"
        case .info: "Info"
        case .notice: "Notice"
        case .error: "Error"
        case nil: "Unknown"
        }
    }
}

// MARK: - IdentifiableEvent

/// Thin `Identifiable` wrapper around `DiagnosticEventRecord` used by the sheet
/// presentation, since `DiagnosticEventRecord.id` is `Int64?` (optional) and
/// SwiftUI's `sheet(item:)` requires `Identifiable` with a non-optional `id`.
private struct IdentifiableEvent: Identifiable {
    let record: DiagnosticEventRecord
    var id: String {
        if let rowId = record.id {
            return "db-\(rowId)"
        }
        return "\(record.timestamp)-\(record.event)"
    }
}

// MARK: - Display helpers

private extension DiagnosticLevel {
    static var allPickerCases: [DiagnosticLevel] {
        [.debug, .info, .notice, .error]
    }

    var displayLabel: String {
        switch self {
        case .debug: "Debug"
        case .info: "Info"
        case .notice: "Notice"
        case .error: "Error"
        }
    }
}

private extension DiagnosticCategory {
    var displayLabel: String {
        switch self {
        case .outbox: "Outbox"
        case .composerOutbox: "Composer"
        case .scheduler: "Scheduler"
        case .site: "Site"
        case .offlineDownload: "Offline"
        case .unread: "Unread"
        case .spotlight: "Spotlight"
        case .lifecycle: "Lifecycle"
        }
    }
}
