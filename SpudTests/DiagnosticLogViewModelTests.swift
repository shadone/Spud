//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import Spud
@testable import SpudDataKit

/// Tests for `DiagnosticLogViewModel`.
///
/// Each test uses `AppDatabase.inMemory()` + `DiagnosticLog` to write real events
/// via the protocol, then verifies `shareText()` output and `clear()` behaviour.
/// The view model's `events` array is populated by calling
/// `startObserving(appDatabase:)` and yielding briefly so the initial GRDB
/// observation fires, or by driving `recent()` directly on the `DiagnosticLog`
/// and comparing against `shareText()` output.
@MainActor
struct DiagnosticLogViewModelTests {
    // MARK: - Helpers

    /// Seeds `log` with two events and waits for `vm.events` to populate
    /// via the live GRDB observation.
    private func makeVMWithEvents(
        db: AppDatabase,
        log: DiagnosticLog
    ) async -> DiagnosticLogViewModel {
        await log.record(
            category: .outbox,
            level: .error,
            event: "op.permanentRollback",
            message: "Vote rolled back",
            instance: "lemmy.world",
            metadata: nil
        )
        await log.record(
            category: .scheduler,
            level: .info,
            event: "scheduler.tick",
            message: "Scheduled",
            instance: nil,
            metadata: nil
        )

        let vm = DiagnosticLogViewModel(diagnostics: log)
        vm.startObserving(appDatabase: db)

        // Wait up to 2 s for the initial GRDB observation to fire.
        for _ in 0..<40 {
            if !vm.events.isEmpty { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return vm
    }

    // MARK: - shareText format

    /// `shareText` produces one line per event with LEVEL label, category, event name
    /// and message.
    @Test
    func shareText_formatsEventsCorrectly() async throws {
        let db = try AppDatabase.inMemory()
        let log = DiagnosticLog(appDatabase: db)
        let vm = await makeVMWithEvents(db: db, log: log)

        let text = vm.shareText()
        #expect(text.contains("[ERROR]"))
        #expect(text.contains("op.permanentRollback"))
        #expect(text.contains("[INFO]"))
        #expect(text.contains("scheduler.tick"))
    }

    /// Instance suffix appears when the event has one, and is absent when nil.
    @Test
    func shareText_includesInstanceWhenPresent() async throws {
        let db = try AppDatabase.inMemory()
        let log = DiagnosticLog(appDatabase: db)
        let vm = await makeVMWithEvents(db: db, log: log)

        let text = vm.shareText()
        #expect(text.contains("[lemmy.world]"))

        // The scheduler.tick event has no instance; its line must not contain the suffix.
        let lines = text.split(separator: "\n")
        let schedulerLine = lines.first { $0.contains("scheduler.tick") }
        #expect(schedulerLine != nil)
        #expect(schedulerLine?.contains("[lemmy.world]") == false)
    }

    /// When there are no events `shareText` returns an empty string.
    @Test
    func shareText_emptyWhenNoEvents() throws {
        let db = try AppDatabase.inMemory()
        let log = DiagnosticLog(appDatabase: db)
        let vm = DiagnosticLogViewModel(diagnostics: log)
        // Do not start observing — events stays [] by default.
        #expect(vm.shareText().isEmpty)
    }

    /// `shareText` output preserves the newest-first ordering produced by GRDB.
    @Test
    func shareText_preservesNewestFirstOrder() async throws {
        let db = try AppDatabase.inMemory()
        let log = DiagnosticLog(appDatabase: db)
        await log.record(
            category: .scheduler,
            level: .info,
            event: "first",
            message: "m1",
            instance: nil,
            metadata: nil
        )
        // Sleep so the timestamps differ.
        try await Task.sleep(for: .milliseconds(15))
        await log.record(
            category: .scheduler,
            level: .info,
            event: "second",
            message: "m2",
            instance: nil,
            metadata: nil
        )

        let vm = DiagnosticLogViewModel(diagnostics: log)
        vm.startObserving(appDatabase: db)
        for _ in 0..<40 {
            if vm.events.count == 2 { break }
            try? await Task.sleep(for: .milliseconds(50))
        }

        let text = vm.shareText()
        let secondRange = text.range(of: "second")
        let firstRange = text.range(of: "first")
        if let s = secondRange, let f = firstRange {
            // "second" was inserted later; GRDB returns newest-first, so
            // "second" should appear before "first" in the export text.
            #expect(s.lowerBound <= f.lowerBound)
        }
    }

    // MARK: - clear

    /// After `clear()` the GRDB table is empty and `shareText` returns an empty string.
    @Test
    func clear_removesAllEvents() async throws {
        let db = try AppDatabase.inMemory()
        let log = DiagnosticLog(appDatabase: db)
        await log.record(
            category: .lifecycle,
            level: .info,
            event: "app.launch",
            message: "Launched",
            instance: nil,
            metadata: nil
        )

        let vm = DiagnosticLogViewModel(diagnostics: log)
        vm.startObserving(appDatabase: db)
        // Wait for initial events to appear.
        for _ in 0..<40 {
            if !vm.events.isEmpty { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(!vm.events.isEmpty)

        await vm.clear()

        // Wait for GRDB observation to emit the post-clear empty array.
        for _ in 0..<40 {
            if vm.events.isEmpty { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(vm.events.isEmpty)
        #expect(vm.shareText().isEmpty)
    }

    // MARK: - Level filter

    /// Setting `minimumLevel` to `.error` hides `.debug` events and shows only `.error` events.
    @Test
    func minimumLevel_filtersEvents() async throws {
        let db = try AppDatabase.inMemory()
        let log = DiagnosticLog(appDatabase: db)
        await log.record(
            category: .scheduler,
            level: .debug,
            event: "scheduler.tick",
            message: "Tick",
            instance: nil,
            metadata: nil
        )
        await log.record(
            category: .outbox,
            level: .error,
            event: "op.permanentRollback",
            message: "Vote rolled back",
            instance: nil,
            metadata: nil
        )

        let vm = DiagnosticLogViewModel(diagnostics: log)
        vm.startObserving(appDatabase: db)

        // Wait for initial events (both should appear at the default .debug minimum level).
        for _ in 0..<40 {
            if vm.events.count == 2 { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(vm.events.count == 2)

        // Raise the minimum level to .error — only the error event should remain.
        vm.minimumLevel = .error

        for _ in 0..<40 {
            if vm.events.count == 1 { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(vm.events.count == 1)
        #expect(vm.events.first?.event == "op.permanentRollback")
    }

    // MARK: - NOTICE level label

    /// `shareText` uses "NOTICE" for `.notice` level events.
    @Test
    func shareText_noticeLevel_usesNoticeLabel() async throws {
        let db = try AppDatabase.inMemory()
        let log = DiagnosticLog(appDatabase: db)
        await log.record(
            category: .site,
            level: .notice,
            event: "site.degraded",
            message: "Rate limited",
            instance: nil,
            metadata: nil
        )

        let vm = DiagnosticLogViewModel(diagnostics: log)
        vm.startObserving(appDatabase: db)
        for _ in 0..<40 {
            if !vm.events.isEmpty { break }
            try? await Task.sleep(for: .milliseconds(50))
        }

        let text = vm.shareText()
        #expect(text.contains("[NOTICE]"))
        #expect(text.contains("site.degraded"))
    }
}
