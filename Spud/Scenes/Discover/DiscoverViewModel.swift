//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Observation
import OSLog
import SpudDataKit
import SpudUIKit

private let logger = Logger.app

/// Per-community follow progress for the inline Follow control on Discover.
/// Tracks an optimistic, session-local state — communities already subscribed
/// before Discover opened are not pre-populated (that join is the separate
/// "because you follow" surface), so every row starts `.idle`.
enum CommunityFollowState: Equatable {
    case idle
    case inFlight
    case following
}

/// View model for the Discover (Community Explorer) screen. Observes the whole
/// Explorer community directory and derives the rails — Trending and Rising —
/// plus the sortable/searchable "All communities" directory, all via the pure
/// ``ExplorerCommunityDirectory``. Opening a community is delegated to the
/// hosting controller through `onOpenCommunity`; following resolves the
/// community by name and subscribes in place.
@MainActor
@Observable
final class DiscoverViewModel {
    typealias OwnDependencies =
        HasAccountService &
        HasAlertService &
        HasAppDatabase
    typealias Dependencies = OwnDependencies

    @ObservationIgnored
    private let dependencies: OwnDependencies

    @ObservationIgnored
    let accountKeychainId: String

    @ObservationIgnored
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
    /// Liveliest home instances, for the "Browse by instance" rail.
    private(set) var instances: [InstanceSummary] = []
    /// The filtered, sorted, de-duplicated directory.
    private(set) var directory: [CommunityListRow] = []
    /// True until the first directory snapshot arrives.
    private(set) var isLoading = true

    /// When set, the same-name compare sheet is presented.
    var compareTarget: CompareTarget?

    /// Inline Follow progress, keyed by ``CommunityListRow/id``.
    private(set) var followStates: [Int64: CommunityFollowState] = [:]

    var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    @ObservationIgnored
    private var allRows: [CommunityListRow] = []
    @ObservationIgnored
    private let onOpenCommunity: (CommunityListRow) -> Void
    @ObservationIgnored
    private let onOpenPack: (ResolvedStarterPack) -> Void
    @ObservationIgnored
    private let onOpenInstance: (InstanceSummary) -> Void
    @ObservationIgnored
    private let onRequestSignIn: () -> Void
    @ObservationIgnored
    private var observationTask: Task<Void, Never>?

    private var accountService: AccountServiceType {
        dependencies.accountService
    }

    private var alertService: AlertServiceType {
        dependencies.alertService
    }

    init(
        accountKeychainId: String,
        isSignedIn: Bool,
        dependencies: Dependencies,
        onOpenCommunity: @escaping (CommunityListRow) -> Void,
        onOpenPack: @escaping (ResolvedStarterPack) -> Void,
        onOpenInstance: @escaping (InstanceSummary) -> Void,
        onRequestSignIn: @escaping () -> Void
    ) {
        self.accountKeychainId = accountKeychainId
        self.isSignedIn = isSignedIn
        self.dependencies = dependencies
        self.onOpenCommunity = onOpenCommunity
        self.onOpenPack = onOpenPack
        self.onOpenInstance = onOpenInstance
        self.onRequestSignIn = onRequestSignIn

        let appDatabase = dependencies.appDatabase
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

    func openInstance(_ summary: InstanceSummary) {
        onOpenInstance(summary)
    }

    /// The curated-safe communities hosted on `host`, sorted by the current
    /// directory sort. Used to populate the instance browse screen.
    func communities(onInstance host: String) -> [CommunityListRow] {
        ExplorerCommunityDirectory.communities(onInstance: host, in: allRows, sort: sort)
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

    func followState(for row: CommunityListRow) -> CommunityFollowState {
        followStates[row.id] ?? .idle
    }

    /// Follow `row` in place: resolve the community by `name@instance` and
    /// subscribe. Signed-out accounts hit the sign-in gate instead; in-flight or
    /// already-followed rows are ignored.
    func follow(_ row: CommunityListRow) {
        guard isSignedIn else {
            onRequestSignIn()
            return
        }
        guard followState(for: row) == .idle else { return }

        followStates[row.id] = .inFlight
        Haptics.tap()

        Task { [weak self] in
            guard let self else { return }
            do {
                let lemmyService = accountService.lemmyService(forAccountKeychainId: accountKeychainId)
                let serverCommunityId = try await lemmyService
                    .fetchCommunityInfo(communityName: "\(row.name)@\(row.instanceHost)")
                if Task.isCancelled { return }
                try await lemmyService.setSubscribed(serverCommunityId: serverCommunityId, subscribed: true)
                followStates[row.id] = .following
            } catch {
                followStates[row.id] = .idle
                alertService.handle(error, for: .setSubscribed)
            }
        }
    }

    private func recomputeRails() {
        starterPacks = StarterPackCatalog.resolve(using: allRows)
        trending = ExplorerCommunityDirectory.trending(in: allRows, limit: 12)
        rising = ExplorerCommunityDirectory.rising(in: allRows, limit: 12)
        instances = ExplorerCommunityDirectory.topInstances(in: allRows, limit: 12)
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
