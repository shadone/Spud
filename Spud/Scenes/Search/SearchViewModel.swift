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

    /// Set synchronously on each keystroke when the query is a recognized Lemmy
    /// URL. While non-nil the text search is skipped (searching a URL string is
    /// meaningless) and the VC shows an "Open in Spud" row instead.
    private(set) var urlSuggestion: SearchURLSuggestion?

    // MARK: Private

    @ObservationIgnored
    let accountScope: AccountScope
    @ObservationIgnored
    private let alertService: AlertServiceType
    @ObservationIgnored
    private let preferencesService: PreferencesServiceType
    @ObservationIgnored
    private let isKnownInstance: (String) -> Bool
    /// Client-side instance search over the bundled Lemmy Explorer directory.
    /// Lemmy has no federated instance search type, so the `.instances` scope is
    /// served locally. Injected (production reads `AppDatabase`; tests stub).
    @ObservationIgnored
    private let searchInstances: @Sendable (String) -> [SearchInstanceResult]

    /// The in-flight (or pending-debounce) search. Cancelled and replaced on
    /// every new query / scope change.
    @ObservationIgnored
    private var searchTask: Task<Void, Never>?

    // MARK: Functions

    init(
        accountScope: AccountScope,
        alertService: AlertServiceType,
        preferencesService: PreferencesServiceType,
        isKnownInstance: @escaping (String) -> Bool,
        searchInstances: @escaping @Sendable (String) -> [SearchInstanceResult]
    ) {
        self.accountScope = accountScope
        self.alertService = alertService
        self.preferencesService = preferencesService
        self.isKnownInstance = isKnownInstance
        self.searchInstances = searchInstances
    }

    deinit {
        searchTask?.cancel()
    }

    /// Called on each keystroke. Trims, then either resets to the initial state
    /// (empty query), offers an "Open in Spud" row for a recognized Lemmy URL,
    /// or schedules a debounced text search.
    func queryChanged(_ rawQuery: String) {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        query = trimmed

        searchTask?.cancel()

        urlSuggestion = SearchURLDetector.detect(query: trimmed, isKnownInstance: isKnownInstance)

        guard !trimmed.isEmpty else {
            phase = .initial
            results = SearchResults()
            return
        }

        // A recognized URL is offered as an "Open in Spud" row; skip the search.
        guard urlSuggestion == nil else {
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

        // A recognized URL is offered as an "Open in Spud" row; skip the search.
        guard urlSuggestion == nil else { return }

        scheduleSearch(query: query, debounced: false)
    }

    /// Called when the user taps Search on the keyboard. Runs immediately.
    func submit() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // A recognized URL is offered as an "Open in Spud" row; skip the search.
        guard urlSuggestion == nil else { return }
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
        // `.instances` is served client-side from the bundled Explorer directory;
        // Lemmy has no federated instance search type.
        if scope.isInstances {
            await performInstanceSearch(query: query)
            return
        }

        guard let type = scope.searchType else {
            // Defensive: every non-instances scope has a search type.
            results = SearchResults()
            lastSearchedQuery = query
            phase = .loaded
            return
        }

        let lemmyService = accountScope.lemmyService

        do {
            let response = try await lemmyService.search(
                query: query,
                type: type,
                sort: .TopAll,
                listingType: .All,
                page: 1
            )
            if Task.isCancelled { return }

            results = SearchResults(response: response).filteringNsfw(!preferencesService.showNsfw)
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

    /// Runs the client-side Explorer instance search off the main actor (the
    /// `*Sync` helper reads GRDB), then applies the results back on the main actor.
    private func performInstanceSearch(query: String) async {
        let searchInstances = searchInstances
        let matches = await Task.detached(priority: .userInitiated) {
            searchInstances(query)
        }.value
        if Task.isCancelled { return }

        var results = SearchResults()
        results.instances = matches
        self.results = results
        lastSearchedQuery = query
        phase = .loaded
    }
}
