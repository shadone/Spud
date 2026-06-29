//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Observation
import SpudDataKit

/// Drives ``AccountSwitcherView``: holds the live list of account rows, kept in
/// sync with the database via `observeAccountListRows()`. `@Observable` so the
/// SwiftUI sheet re-renders whenever an account is added, removed, or the
/// default changes (e.g. after the user taps a row to switch).
@MainActor
@Observable
final class AccountSwitcherViewModel {
    /// The non-service account rows, in the observation's order (signed-in
    /// first, then anonymous). The view splits them into its two sections.
    private(set) var rows: [AccountListRow] = []

    /// The DB observation task. `@ObservationIgnored` so reading/writing it
    /// doesn't churn observation; the task weak-captures `self`, so it can't keep
    /// the model alive. Cancelled in `deinit` (the reliable backstop) and,
    /// eagerly, via `stop()` when the sheet is dismissed.
    @ObservationIgnored
    private var observationTask: Task<Void, Never>?

    private let appDatabase: AppDatabase

    init(appDatabase: AppDatabase) {
        self.appDatabase = appDatabase
        startObserving()
    }

    deinit {
        // `deinit` of a `@MainActor` type runs on the main actor, so the
        // `@MainActor` `observationTask` is safe to cancel here. This is the
        // backstop that guarantees the DB observation is torn down regardless of
        // how the sheet goes away (matches `DiscoverViewModel` / `PersonViewModel`).
        observationTask?.cancel()
    }

    /// Eagerly stops the underlying DB observation when the sheet is dismissed,
    /// so it doesn't outlive the visible screen even before the view model is
    /// deallocated. `deinit` is the reliable backstop.
    func stop() {
        observationTask?.cancel()
        observationTask = nil
    }

    private func startObserving() {
        observationTask?.cancel()
        observationTask = Task { [weak self, appDatabase] in
            for await rows in appDatabase.observeAccountListRows() {
                if Task.isCancelled { break }
                self?.rows = rows
            }
        }
    }
}
