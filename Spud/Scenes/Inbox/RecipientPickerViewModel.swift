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
import SpudUtilKit

private let logger = Logger.app

/// The phase the recipient picker is in. Drives which of the designed states the
/// view controller renders. Mirrors `SearchPhase` but is scoped to the
/// single-purpose user search, so the two evolve independently.
enum RecipientPickerPhase: Equatable {
    /// No query has been entered yet — show the "search for someone" prompt.
    case initial
    /// A query is in flight.
    case loading
    /// Results arrived (possibly empty — the VC distinguishes empty to show the
    /// no-results state).
    case loaded
    /// The last search failed.
    case error
}

/// Drives the "New message" recipient picker: a single-purpose, debounced search
/// over Lemmy *users* (the `.Users` search type). Holds the query, the current
/// phase, and the decoded `[SearchUserResult]`.
///
/// Input is debounced (~300ms) and each new query cancels the previous in-flight
/// request, so fast typing only ever keeps one request alive (the same pattern
/// as `SearchViewModel`). The actual search is injected as a closure so the view
/// model is testable without a live `LemmyService`: production wires it to
/// `accountScope.lemmyService.search(type: .Users, …)`; tests inject a stub.
@MainActor
@Observable
final class RecipientPickerViewModel {
    /// Debounce window between the last keystroke and the search call.
    private static let debounce: Duration = .milliseconds(300)

    // MARK: Observable state

    private(set) var query: String = ""
    private(set) var phase: RecipientPickerPhase = .initial
    private(set) var results: [SearchUserResult] = []

    /// The query that produced `results` — used by the no-results state copy so
    /// it quotes the term that actually returned nothing, not the live text.
    private(set) var lastSearchedQuery: String = ""

    // MARK: Private

    /// Runs one user search for a trimmed, non-empty query and returns the
    /// decoded results. Throws on network/decoding failure (drives `.error`).
    /// Injected so the search can be stubbed in tests.
    @ObservationIgnored
    private let searchUsers: @MainActor (String) async throws -> [SearchUserResult]

    /// The in-flight (or pending-debounce) search. Cancelled and replaced on
    /// every new query.
    @ObservationIgnored
    private var searchTask: Task<Void, Never>?

    // MARK: Functions

    init(searchUsers: @escaping @MainActor (String) async throws -> [SearchUserResult]) {
        self.searchUsers = searchUsers
    }

    deinit {
        searchTask?.cancel()
    }

    /// Called on each keystroke. Trims, then either resets to the initial state
    /// (empty query) or schedules a debounced user search.
    func queryChanged(_ rawQuery: String) {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        query = trimmed

        searchTask?.cancel()

        guard !trimmed.isEmpty else {
            phase = .initial
            results = []
            return
        }

        scheduleSearch(query: trimmed, debounced: true)
    }

    /// Called when the user taps Search on the keyboard. Runs immediately
    /// (no debounce).
    func submit() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        searchTask?.cancel()

        // Mirror `queryChanged`: an empty/whitespace query never searches and
        // resets to the initial prompt rather than leaving a stale phase/results.
        guard !trimmed.isEmpty else {
            phase = .initial
            results = []
            return
        }

        scheduleSearch(query: trimmed, debounced: false)
    }

    private func scheduleSearch(query: String, debounced: Bool) {
        phase = .loading

        searchTask = Task { [weak self] in
            if debounced {
                try? await Task.sleep(for: Self.debounce)
            }
            if Task.isCancelled { return }
            await self?.performSearch(query: query)
        }
    }

    private func performSearch(query: String) async {
        do {
            let users = try await searchUsers(query)
            if Task.isCancelled { return }
            results = users
            lastSearchedQuery = query
            phase = .loaded
        } catch {
            if Task.isCancelled { return }
            logger.error("Recipient search failed: \(String(describing: error), privacy: .public)")
            results = []
            lastSearchedQuery = query
            phase = .error
        }
    }
}
