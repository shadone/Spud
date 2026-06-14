//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Observation
import OSLog
import SpudDataKit

private let logger = Logger.app

/// View model for the Discover (Community Explorer) screen. Observes the whole
/// Explorer community directory and derives the rails — Trending and Rising —
/// plus the sortable/searchable "All communities" directory, all via the pure
/// ``ExplorerCommunityDirectory``. Opening a community is delegated to the
/// hosting controller through `onOpenCommunity`.
@MainActor
@Observable
final class DiscoverViewModel {
    let isSignedIn: Bool

    /// Free-text filter from the nav-bar search controller.
    var searchText: String = "" {
        didSet { recomputeDirectory() }
    }

    /// Sort applied to the "All communities" directory.
    var sort: ExplorerCommunitySort = .recommended {
        didSet { recomputeDirectory() }
    }

    /// Curated bundles a new user can follow together, with live stats.
    private(set) var starterPacks: [ResolvedStarterPack] = []
    /// Busiest communities this week.
    private(set) var trending: [CommunityListRow] = []
    /// Small communities punching above their size.
    private(set) var rising: [CommunityListRow] = []
    /// The filtered, sorted, de-duplicated directory.
    private(set) var directory: [CommunityListRow] = []
    /// True until the first directory snapshot arrives.
    private(set) var isLoading = true

    /// When set, the same-name compare sheet is presented.
    var compareTarget: CompareTarget?

    var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var allRows: [CommunityListRow] = []
    private let onOpenCommunity: (CommunityListRow) -> Void
    private let onOpenPack: (ResolvedStarterPack) -> Void
    @ObservationIgnored
    private var observationTask: Task<Void, Never>?

    init(
        appDatabase: AppDatabase,
        isSignedIn: Bool,
        onOpenCommunity: @escaping (CommunityListRow) -> Void,
        onOpenPack: @escaping (ResolvedStarterPack) -> Void
    ) {
        self.isSignedIn = isSignedIn
        self.onOpenCommunity = onOpenCommunity
        self.onOpenPack = onOpenPack

        observationTask = Task { [weak self] in
            for await rows in appDatabase.observeExplorerCommunityListRows() {
                if Task.isCancelled { break }
                guard let self else { return }
                allRows = rows
                recomputeRails()
                recomputeDirectory()
                isLoading = false
            }
        }
    }

    deinit {
        observationTask?.cancel()
    }

    func open(_ row: CommunityListRow) {
        onOpenCommunity(row)
    }

    func openPack(_ pack: ResolvedStarterPack) {
        onOpenPack(pack)
    }

    /// Present the same-name compare sheet for `row`, listing every server that
    /// hosts a community with this name, busiest first.
    func compare(_ row: CommunityListRow) {
        compareTarget = CompareTarget(
            name: row.name,
            displayName: row.displayName,
            variants: ExplorerCommunityDirectory.variants(of: row.name, in: allRows)
        )
    }

    /// Dismiss the compare sheet and open the chosen variant's community page.
    func openFromCompare(_ row: CommunityListRow) {
        compareTarget = nil
        onOpenCommunity(row)
    }

    private func recomputeRails() {
        starterPacks = StarterPackCatalog.resolve(using: allRows)
        trending = ExplorerCommunityDirectory.trending(in: allRows, limit: 12)
        rising = ExplorerCommunityDirectory.rising(in: allRows, limit: 12)
    }

    private func recomputeDirectory() {
        // Curated surfaces stay clean: NSFW and suspicious are filtered out, and
        // same-name communities collapse to one canonical entry.
        let filter = ExplorerCommunityFilter(hideNsfw: true, hideSuspicious: true)
        directory = ExplorerCommunityDirectory.apply(
            to: allRows,
            query: searchText,
            filter: filter,
            sort: sort,
            dedupeSameName: true
        )
    }
}
