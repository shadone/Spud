//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import Observation
import OSLog
import SpudDataKit

private let logger = Logger.app

/// Drives the Search screen. Holds the query, the selected scope, the current
/// phase, and the decoded results. Input is debounced (~300ms) and each new
/// query cancels the previous in-flight request, so fast typing only ever
/// keeps one request alive.
@MainActor
@Observable
final class SearchViewModel {
    /// Debounce window between the last keystroke and the API call.
    private static let debounce: Duration = .milliseconds(300)

    private static let resultLimit: Int64 = 30

    // MARK: Observable state

    var query: String = ""
    var scope: SearchScope = .posts
    var phase: SearchPhase = .initial
    private(set) var results = SearchResults()

    /// The query that produced `results` - used by the no-results state copy so
    /// it quotes the term that actually returned nothing, not the live text.
    private(set) var lastSearchedQuery: String = ""

    // MARK: Private

    let accountKeychainId: String

    @ObservationIgnored
    private let accountService: AccountServiceType
    @ObservationIgnored
    private let alertService: AlertServiceType

    /// The in-flight (or pending-debounce) search. Cancelled and replaced on
    /// every new query / scope change.
    @ObservationIgnored
    private var searchTask: Task<Void, Never>?

    // MARK: Functions

    init(
        accountKeychainId: String,
        accountService: AccountServiceType,
        alertService: AlertServiceType
    ) {
        self.accountKeychainId = accountKeychainId
        self.accountService = accountService
        self.alertService = alertService
    }

    deinit {
        searchTask?.cancel()
    }

    /// Called on each keystroke. Trims, then either resets to the initial state
    /// (empty query) or schedules a debounced search.
    func queryChanged(_ rawQuery: String) {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        query = trimmed

        searchTask?.cancel()

        guard !trimmed.isEmpty else {
            phase = .initial
            results = SearchResults()
            return
        }

        scheduleSearch(query: trimmed, debounced: true)
    }

    /// Called when the user picks a different scope. Re-runs the active query
    /// immediately (no debounce) against the new scope.
    func scopeChanged(_ newScope: SearchScope) {
        guard newScope != scope else { return }
        scope = newScope

        searchTask?.cancel()

        guard !query.isEmpty else {
            phase = .initial
            return
        }

        scheduleSearch(query: query, debounced: false)
    }

    /// Called when the user taps Search on the keyboard. Runs immediately.
    func submit() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        searchTask?.cancel()
        scheduleSearch(query: trimmed, debounced: false)
    }

    private func scheduleSearch(query: String, debounced: Bool) {
        let scope = scope
        phase = .loading

        searchTask = Task { [weak self] in
            if debounced {
                try? await Task.sleep(for: Self.debounce)
            }
            if Task.isCancelled { return }
            await self?.performSearch(query: query, scope: scope)
        }
    }

    private func performSearch(query: String, scope: SearchScope) async {
        let lemmyService = accountService.lemmyService(forAccountKeychainId: accountKeychainId)

        do {
            let response = try await lemmyService.search(
                query: query,
                type: scope.searchType,
                sort: .TopAll,
                listingType: .All,
                page: 1
            )
            if Task.isCancelled { return }

            results = SearchResults(response: response)
            lastSearchedQuery = query
            phase = .loaded
        } catch {
            if Task.isCancelled { return }
            logger.error("Search failed: \(String(describing: error), privacy: .public)")
            alertService.handle(error, for: .search)
            results = SearchResults()
            lastSearchedQuery = query
            phase = .error
        }
    }
}
