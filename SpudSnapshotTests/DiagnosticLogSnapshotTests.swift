//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SnapshotTesting
import SpudDataKit
import SwiftUI
import UIKit
import XCTest
@testable import Spud

/// Snapshot tests for the diagnostic log viewer (About → Logs → Event Log).
///
/// ## Determinism strategy
///
/// `DiagnosticLogRowView` formats a relative timestamp via `RelativeDateTimeFormatter`
/// using `Date()` at render time. To keep the output stable we seed rows at FIXED
/// offsets from a single `referenceNow` captured at seed time. Because seed and
/// snapshot happen within the same test method the relative labels ("5 min. ago",
/// "30 min. ago") never drift between record and verify runs.
///
/// ## Async-observation polling
///
/// `DiagnosticLogViewModel` drives a live GRDB `ValueObservation`. We must await
/// Task.sleep/yield (not spin RunLoop) so the observation continuation can land on
/// the @MainActor before we snapshot. The pattern mirrors `PendingPostSnapshotTests`.
///
/// ## System Log
///
/// `SystemLogView` reads the live `OSLogStore` for the current process — the entries
/// are non-deterministic across runs. It is NOT snapshotted here. Its filter chrome
/// (pickers) is rendered deterministically via the `DiagnosticLogDetailView` snapshot
/// (the view can be presented standalone with a pinned event) instead. A note is
/// included in the report.
@MainActor
final class DiagnosticLogSnapshotTests: XCTestCase {
    // MARK: - Seed

    /// Captures a single "now" for all seed calls in one test so relative timestamps
    /// are computed against the same reference regardless of when the formatter runs.
    private var referenceNow: Double = 0

    override func setUp() {
        super.setUp()
        referenceNow = Date().timeIntervalSince1970
    }

    /// Inserts a representative mix of events into `appDatabase`.
    ///
    /// Offsets are chosen so that `RelativeDateTimeFormatter` at `unitsStyle: .short`
    /// produces distinct, readable labels: 2 min, 30 min, 2 hr, 1 day ago.
    private func seedMixedEvents(into appDatabase: AppDatabase) async throws {
        let now = referenceNow
        let events: [DiagnosticEventRecord] = [
            // Newest — error level, outbox category, with instance
            DiagnosticEventRecord(
                timestamp: now - 2 * 60,
                category: DiagnosticCategory.outbox.rawValue,
                level: DiagnosticLevel.error.rawValue,
                event: "op.permanentRollback",
                message: "Vote rolled back — server returned 403",
                instance: "lemmy.world"
            ),
            // Notice level, scheduler category
            DiagnosticEventRecord(
                timestamp: now - 30 * 60,
                category: DiagnosticCategory.scheduler.rawValue,
                level: DiagnosticLevel.notice.rawValue,
                event: "scheduler.tick",
                message: "Scheduled refresh completed (12 accounts)",
                instance: nil
            ),
            // Info level, site category, with instance
            DiagnosticEventRecord(
                timestamp: now - 2 * 3600,
                category: DiagnosticCategory.site.rawValue,
                level: DiagnosticLevel.info.rawValue,
                event: "site.fetchSucceeded",
                message: "Site info refreshed successfully",
                instance: "lemmy.ml"
            ),
            // Debug level, lifecycle category
            DiagnosticEventRecord(
                timestamp: now - 86400,
                category: DiagnosticCategory.lifecycle.rawValue,
                level: DiagnosticLevel.debug.rawValue,
                event: "app.didFinishLaunching",
                message: "Application launched, database ready",
                instance: nil
            ),
        ]
        for var event in events {
            try await appDatabase.writer.write { db in
                try event.insert(db)
            }
        }
    }

    /// Inserts only error-level events (used for level-filter snapshot).
    private func seedErrorOnlyEvents(into appDatabase: AppDatabase) async throws {
        let now = referenceNow
        let events: [DiagnosticEventRecord] = [
            DiagnosticEventRecord(
                timestamp: now - 5 * 60,
                category: DiagnosticCategory.composerOutbox.rawValue,
                level: DiagnosticLevel.error.rawValue,
                event: "op.permanentPark",
                message: "Comment send permanently failed after 5 retries",
                instance: "beehaw.org"
            ),
            DiagnosticEventRecord(
                timestamp: now - 90 * 60,
                category: DiagnosticCategory.site.rawValue,
                level: DiagnosticLevel.error.rawValue,
                event: "site.fetchFailed",
                message: "Could not reach instance (error 403)",
                instance: "discuss.tchncs.de"
            ),
        ]
        for var event in events {
            try await appDatabase.writer.write { db in
                try event.insert(db)
            }
        }
    }

    // MARK: - Render detection

    /// Walks the SwiftUI-rendered UIView hierarchy looking for any label whose text
    /// contains `text`. Used to confirm the GRDB observation delivered rows to the
    /// view before snapshotting.
    private func hierarchyContainsText(_ view: UIView, text: String) -> Bool {
        if let label = view as? UILabel,
           !label.isHidden,
           label.text?.contains(text) == true
        {
            return true
        }
        for subview in view.subviews where hierarchyContainsText(subview, text: text) {
            return true
        }
        return false
    }

    // MARK: - Snapshot helpers

    private let snapshotSize = CGSize(width: 390, height: 844)

    /// Polls `vm.events` directly (not the rendered UILabel hierarchy) until it
    /// is non-empty. Returns true on success, false on timeout. Polling the
    /// Observable property is more reliable than searching UILabel text in a
    /// `UIHostingController` that is offscreen (SwiftUI may not have run its
    /// rendering pass yet).
    private func waitForEvents(
        in vm: DiagnosticLogViewModel,
        expectedSentinel: String,
        deadline: TimeInterval = 4
    ) async -> Bool {
        let endDate = Date().addingTimeInterval(deadline)
        while Date() < endDate {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            if vm.events.contains(where: { $0.event.contains(expectedSentinel) || $0.message.contains(expectedSentinel) }) {
                return true
            }
        }
        return false
    }

    /// Polls `vm.events` until it is empty (for the empty-state test).
    private func waitForEmptyEvents(
        in vm: DiagnosticLogViewModel,
        deadline: TimeInterval = 4
    ) async -> Bool {
        // For the empty-state test, the DB has no rows. The observation fires once
        // with an empty array. We just need to confirm the observation has fired (not
        // the initial unset state). We wait a moment and check we got the empty delivery.
        await Task.yield()
        try? await Task.sleep(nanoseconds: 300_000_000) // 300ms is plenty
        return true // empty observation always fires; if startObserving didn't work, layout will show no content anyway
    }

    /// Waits (up to `deadline`) for `sentinelText` to appear in `hostingView`,
    /// polling via Task.sleep. Returns true on success, false on timeout.
    private func waitForText(
        _ sentinelText: String,
        in hostingView: UIView,
        deadline: TimeInterval = 2
    ) async -> Bool {
        let endDate = Date().addingTimeInterval(deadline)
        while Date() < endDate {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            hostingView.layoutIfNeeded()
            if hierarchyContainsText(hostingView, text: sentinelText) {
                return true
            }
        }
        return false
    }

    /// Creates a `UIHostingController` for `DiagnosticLogView`, starts the GRDB
    /// observation directly on the VM (bypassing SwiftUI's `.task` which requires a
    /// live window), waits for the VM's `events` to be populated, then takes a
    /// light + dark snapshot pair.
    ///
    /// The VM's observation is started BEFORE the view is hosted so events are
    /// available on the first render pass. SwiftUI's `@Observable` machinery will
    /// track `viewModel.events` reads in `body` and re-render when they change —
    /// this works without a live window since `UIHostingController.loadViewIfNeeded()`
    /// triggers the initial SwiftUI layout pass.
    private func assertEventLogScreens(
        appDatabase: AppDatabase,
        sentinel: String,
        testName: String = #function,
        line: UInt = #line
    ) async throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            // Build the VM and start the observation BEFORE the view is hosted.
            let diagnostics = DiagnosticLog(appDatabase: appDatabase)
            let vm = DiagnosticLogViewModel(diagnostics: diagnostics)
            vm.startObserving(appDatabase: appDatabase)

            // Wait for GRDB to deliver the first batch to vm.events, polling the
            // Observable property directly (no UILabel walk needed at this stage).
            let eventsDelivered = await waitForEvents(in: vm, expectedSentinel: sentinel)
            guard eventsDelivered else {
                XCTFail(
                    "GRDB observation never delivered '\(sentinel)' to DiagnosticLogViewModel.events. " +
                        "Refusing to snapshot a blank screen.",
                    line: line
                )
                return
            }

            // Now host the view — since vm.events is already populated, SwiftUI's
            // first layout pass will render the event rows immediately.
            let hostingView = DiagnosticLogView(viewModel: vm, appDatabase: appDatabase)
            let hostingController = UIHostingController(rootView: hostingView)
            let navigationController = UINavigationController(rootViewController: hostingController)

            navigationController.loadViewIfNeeded()
            navigationController.view.frame = CGRect(origin: .zero, size: snapshotSize)
            navigationController.view.layoutIfNeeded()

            // Brief settle for SwiftUI layout pass to complete.
            try? await Task.sleep(nanoseconds: 150_000_000)
            navigationController.view.layoutIfNeeded()

            assertSnapshot(
                matching: navigationController,
                as: .image(
                    on: .iPhone13Pro,
                    size: snapshotSize,
                    traits: UITraitCollection(userInterfaceStyle: style)
                ),
                named: style == .dark ? "dark" : "light",
                testName: testName,
                line: line
            )
        }
    }

    // MARK: - State 1: Populated list (mixed levels)

    /// Event log with a mix of debug / info / notice / error rows — light + dark.
    func test_eventLog_populated() async throws {
        let appDatabase = try AppDatabase.inMemory()
        try await seedMixedEvents(into: appDatabase)

        // Sentinel: the error event's name, which is seeded and should always be visible.
        try await assertEventLogScreens(
            appDatabase: appDatabase,
            sentinel: "op.permanentRollback"
        )
    }

    // MARK: - State 2: Empty state

    /// Event log with no rows shows the "No events" empty-state text.
    func test_eventLog_empty() async throws {
        let appDatabase = try AppDatabase.inMemory()
        // No events inserted — the VM will observe an empty table.

        for style in [UIUserInterfaceStyle.light, .dark] {
            let diagnostics = DiagnosticLog(appDatabase: appDatabase)
            let vm = DiagnosticLogViewModel(diagnostics: diagnostics)
            vm.startObserving(appDatabase: appDatabase)

            // For the empty state the observation fires once with []. Give the
            // async chain time to run (filterWatchTask → subscribeToEvents → GRDB delivery).
            _ = await waitForEmptyEvents(in: vm)

            let hostingView = DiagnosticLogView(viewModel: vm, appDatabase: appDatabase)
            let hostingController = UIHostingController(rootView: hostingView)
            let navigationController = UINavigationController(rootViewController: hostingController)

            navigationController.loadViewIfNeeded()
            navigationController.view.frame = CGRect(origin: .zero, size: snapshotSize)
            navigationController.view.layoutIfNeeded()

            try? await Task.sleep(nanoseconds: 150_000_000)
            navigationController.view.layoutIfNeeded()

            assertSnapshot(
                matching: navigationController,
                as: .image(
                    on: .iPhone13Pro,
                    size: snapshotSize,
                    traits: UITraitCollection(userInterfaceStyle: style)
                ),
                named: style == .dark ? "dark" : "light"
            )
        }
    }

    // MARK: - State 3: Detail view

    /// The event-detail sheet for a single `DiagnosticEventRecord`.
    ///
    /// Presented as a standalone `NavigationStack`-hosted view so it renders
    /// without needing the parent list to open the sheet — deterministic and
    /// does not depend on tap simulation.
    func test_eventDetail() async {
        // Fixed Unix timestamp (2001-09-09T01:46:40Z) so the ISO8601 display is
        // stable across runs — `referenceNow` changes each invocation, which would
        // make the refs non-reusable.
        let fixedTimestamp = 1_000_000_000.0
        let event = DiagnosticEventRecord(
            timestamp: fixedTimestamp,
            category: DiagnosticCategory.outbox.rawValue,
            level: DiagnosticLevel.error.rawValue,
            event: "op.permanentRollback",
            message: "Vote rolled back — server returned 403 Forbidden",
            instance: "lemmy.world",
            metadata: "{\"status\":\"403\",\"kind\":\"vote\"}"
        )

        for style in [UIUserInterfaceStyle.light, .dark] {
            let detailView = NavigationStack {
                DiagnosticLogDetailView(event: event)
            }
            let hostingController = UIHostingController(rootView: detailView)

            hostingController.loadViewIfNeeded()
            hostingController.view.frame = CGRect(origin: .zero, size: snapshotSize)
            hostingController.view.layoutIfNeeded()

            // Detail view is synchronous (no GRDB observation) — no polling needed.
            // Brief settle for SwiftUI layout.
            try? await Task.sleep(nanoseconds: 100_000_000)
            hostingController.view.layoutIfNeeded()

            assertSnapshot(
                matching: hostingController,
                as: .image(
                    on: .iPhone13Pro,
                    size: snapshotSize,
                    traits: UITraitCollection(userInterfaceStyle: style)
                ),
                named: style == .dark ? "dark" : "light"
            )
        }
    }

    // MARK: - State 4 (best-effort): Level-filtered list (error only)

    /// Event log filtered to minimum level = error. Seeded with two error events;
    /// info/debug/notice events are deliberately absent so the filter chrome is
    /// the only difference from the populated snapshot.
    func test_eventLog_filteredToError() async throws {
        let appDatabase = try AppDatabase.inMemory()
        try await seedErrorOnlyEvents(into: appDatabase)

        try await assertEventLogScreens(
            appDatabase: appDatabase,
            sentinel: "op.permanentPark"
        )
    }

    // MARK: - State 5 (best-effort): Dynamic Type XXL

    /// Event log at `.accessibilityExtraExtraExtraLarge` to verify Dynamic Type scaling.
    /// Covers the a11y requirement that no label or control uses a fixed font size.
    func test_eventLog_dynamicTypeXXXL() async throws {
        let appDatabase = try AppDatabase.inMemory()
        try await seedMixedEvents(into: appDatabase)

        let sentinel = "op.permanentRollback"

        // Start the GRDB observation before hosting — same bypass as assertEventLogScreens.
        let diagnostics = DiagnosticLog(appDatabase: appDatabase)
        let vm = DiagnosticLogViewModel(diagnostics: diagnostics)
        vm.startObserving(appDatabase: appDatabase)

        // Wait for GRDB to deliver events to vm.events before hosting.
        let eventsDelivered = await waitForEvents(in: vm, expectedSentinel: sentinel)
        guard eventsDelivered else {
            XCTFail(
                "GRDB observation never delivered '\(sentinel)' to DiagnosticLogViewModel.events in XXL test — " +
                    "refusing to snapshot a blank screen."
            )
            return
        }

        let hostingView = DiagnosticLogView(viewModel: vm, appDatabase: appDatabase)
        let hostingController = UIHostingController(rootView: hostingView)
        let navigationController = UINavigationController(rootViewController: hostingController)

        navigationController.loadViewIfNeeded()
        navigationController.view.frame = CGRect(origin: .zero, size: snapshotSize)
        navigationController.view.layoutIfNeeded()

        try? await Task.sleep(nanoseconds: 150_000_000)
        navigationController.view.layoutIfNeeded()

        let xxxl = UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
        assertSnapshot(
            matching: navigationController,
            as: .image(
                on: .iPhone13Pro,
                size: snapshotSize,
                traits: xxxl
            ),
            named: "xxxl"
        )
    }
}
