//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Observation
import SpudDataKit

@Observable
@MainActor
final class ActivityViewModel {
    /// The default active-filter set. An empty set shows every activity type;
    /// the funnel reset returns to this, and it is the seed when no
    /// `initialFilters` are supplied. The footprint rail's "default glance"
    /// visibility is keyed off equality with this set.
    static let defaultFilters: Set<ActivityFilterType> = []

    // MARK: Observable state

    private(set) var items: [ActivityItem] = []
    private(set) var loadState: ActivityLoadState = .idle
    var activeFilters: Set<ActivityFilterType> = []
    var searchQuery: String = ""

    // MARK: Private

    private let coordinator: ActivityCoordinator
    private let accountId: Int64

    // `@ObservationIgnored` so these stay plain stored properties (not tracked
    // through the main-actor `@Observable` registrar) - otherwise the nonisolated
    // `deinit` can't reference them to cancel the streams.
    @ObservationIgnored private var itemStreamTask: Task<Void, Never>?
    @ObservationIgnored private var statusStreamTask: Task<Void, Never>?
    @ObservationIgnored private var searchDebounceTask: Task<Void, Never>?

    // MARK: Functions

    /// Creates an ActivityViewModel.
    ///
    /// - Parameters:
    ///   - coordinator: The data coordinator that drives the activity stream.
    ///   - accountId: Row id of the account whose activity is shown.
    ///   - initialFilters: The filter chips that should be active when the screen
    ///     first opens. Pass an empty set to show all activity (the default).
    init(coordinator: ActivityCoordinator, accountId: Int64, initialFilters: Set<ActivityFilterType> = []) {
        self.coordinator = coordinator
        self.accountId = accountId
        activeFilters = initialFilters
    }

    /// Cancels the long-lived streams on dismissal. Without this, the
    /// `itemStreamTask` / `statusStreamTask` `for await` loops iterate forever and
    /// hold the `ActivityCoordinator` actor (and its GRDB observation) alive past
    /// the screen's lifetime - one leak per push/pop. Cancelling lets each
    /// `AsyncStream`'s `onTermination` fire the coordinator's `stopStreaming`, so
    /// the actor and observation tear down. `stop()` does the same eagerly (e.g.
    /// on `viewDidDisappear`); both are safe to call.
    deinit {
        itemStreamTask?.cancel()
        statusStreamTask?.cancel()
        searchDebounceTask?.cancel()
    }

    func start() {
        restartItemStream()
        startStatusStream()
    }

    func stop() {
        itemStreamTask?.cancel()
        statusStreamTask?.cancel()
        searchDebounceTask?.cancel()
    }

    /// Re-subscribes the item stream from scratch, which resets the coordinator's
    /// pagination and re-fetches the first authored page (the local observation
    /// re-emits on its own). Backs pull-to-refresh.
    func refresh() {
        restartItemStream()
    }

    func toggleFilter(_ filter: ActivityFilterType) {
        if activeFilters.contains(filter) {
            activeFilters.remove(filter)
        } else {
            activeFilters.insert(filter)
        }
        restartItemStream()
    }

    func resetFilters() {
        activeFilters = Self.defaultFilters
        searchQuery = ""
        searchDebounceTask?.cancel()
        restartItemStream()
    }

    func loadMore() {
        Task {
            await coordinator.loadMore()
        }
    }

    func onSearchQueryChanged() {
        searchDebounceTask?.cancel()
        searchDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            if Task.isCancelled { return }
            self?.restartItemStream()
        }
    }

    // MARK: Private

    private func restartItemStream() {
        itemStreamTask?.cancel()
        let filters = activeFilters
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let searchArg: String? = query.isEmpty ? nil : query
        let coordinator = coordinator
        let accountId = accountId
        itemStreamTask = Task { [weak self] in
            let stream = await coordinator.activityStream(
                accountId: accountId,
                filters: filters,
                searchQuery: searchArg
            )
            for await newItems in stream {
                if Task.isCancelled { break }
                self?.items = newItems
            }
        }
    }

    private func startStatusStream() {
        statusStreamTask?.cancel()
        let coordinator = coordinator
        statusStreamTask = Task { [weak self] in
            let stream = await coordinator.statusStream()
            for await state in stream {
                if Task.isCancelled { break }
                self?.loadState = state
            }
        }
    }
}
