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
    // MARK: Observable state

    private(set) var items: [ActivityItem] = []
    private(set) var loadState: ActivityLoadState = .idle
    var activeFilters: Set<ActivityFilterType> = []
    var searchQuery: String = ""

    // MARK: Private

    private let coordinator: ActivityCoordinator
    private let accountId: Int64

    private var itemStreamTask: Task<Void, Never>?
    private var statusStreamTask: Task<Void, Never>?
    private var searchDebounceTask: Task<Void, Never>?

    // MARK: Functions

    init(coordinator: ActivityCoordinator, accountId: Int64) {
        self.coordinator = coordinator
        self.accountId = accountId
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

    func toggleFilter(_ filter: ActivityFilterType) {
        if activeFilters.contains(filter) {
            activeFilters.remove(filter)
        } else {
            activeFilters.insert(filter)
        }
        restartItemStream()
    }

    func resetFilters() {
        activeFilters = []
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
