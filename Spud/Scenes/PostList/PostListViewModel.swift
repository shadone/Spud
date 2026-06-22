//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
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

enum FeedLoadState: Equatable {
    /// Initial fetch in flight. `slow == true` after the escalation threshold.
    case loading(slow: Bool)
    /// At least one post is visible.
    case loaded
    /// The fetch succeeded but there are no posts.
    case empty
    /// The initial fetch failed.
    case failed(LoadFailure)
}

enum PaginationState: Equatable {
    case idle
    case loading
    case failed
}

@MainActor
@Observable
final class PostListViewModel {
    typealias OwnDependencies = HasAccountService & HasReachabilityMonitor
    typealias Dependencies = OwnDependencies

    @ObservationIgnored
    private let dependencies: OwnDependencies

    @ObservationIgnored
    let accountScope: AccountScope

    var feed: FeedHandle
    var accountKeychainId: String {
        accountScope.accountKeychainId
    }

    var navigationTitle: String

    private(set) var loadState: FeedLoadState = .loading(slow: false)
    private(set) var paginationState: PaginationState = .idle

    /// Diagnostics from the most recent failure, for the "Copy details" action.
    @ObservationIgnored
    private(set) var lastFailureDiagnostics: String?

    @ObservationIgnored
    private let fetchFeedOperation: @MainActor (String?) async throws -> String?
    @ObservationIgnored
    private let slowThreshold: Duration
    @ObservationIgnored
    private let hardCapTimeout: Duration

    @ObservationIgnored
    private var nextPageCursor: String?
    @ObservationIgnored
    private var feedExhausted = false
    @ObservationIgnored
    private var hasCompletedInitialFetch = false
    @ObservationIgnored
    private var slowHintTask: Task<Void, Never>?

    private var accountService: AccountServiceType {
        dependencies.accountService
    }

    private var reachabilityMonitor: ReachabilityMonitoring {
        dependencies.reachabilityMonitor
    }

    init(
        feed: FeedHandle,
        accountScope: AccountScope,
        dependencies: Dependencies,
        fetchFeedOperation: (@MainActor (String?) async throws -> String?)? = nil,
        slowThreshold: Duration = .seconds(8),
        hardCapTimeout: Duration = .seconds(25)
    ) {
        self.dependencies = dependencies
        self.accountScope = accountScope
        self.feed = feed
        self.slowThreshold = slowThreshold
        self.hardCapTimeout = hardCapTimeout
        navigationTitle = Self.navigationTitle(for: feed.feedType)
        let scope = accountScope
        self.fetchFeedOperation = fetchFeedOperation ?? { cursor in
            try await scope.lemmyService.fetchFeed(feed, pageCursor: cursor)
        }
    }

    // MARK: - Feed switching (reset state)

    func didChangeSortType(_ sortType: Components.Schemas.SortType) {
        let newFeed = accountService.createFeed(duplicateOf: feed, forAccountKeychainId: accountKeychainId, sortType: sortType)
        resetForNewFeed(newFeed)
    }

    func didClickReload() {
        let newFeed = accountService.createFeed(duplicateOf: feed, forAccountKeychainId: accountKeychainId)
        resetForNewFeed(newFeed)
    }

    func switchFeed(to feedType: FeedType) {
        let newFeed = accountService.createFeed(forAccountKeychainId: accountKeychainId, feedType: feedType)
        resetForNewFeed(newFeed)
    }

    private func resetForNewFeed(_ newFeed: FeedHandle) {
        feed = newFeed
        nextPageCursor = nil
        feedExhausted = false
        hasCompletedInitialFetch = false
        loadState = .loading(slow: false)
        paginationState = .idle
        navigationTitle = Self.navigationTitle(for: newFeed.feedType)
    }

    // MARK: - Initial load

    /// Fetch the first page with the hard-cap timeout and slow-hint escalation.
    /// Leaves `loadState` at `.loading` on success — the GRDB first snapshot
    /// resolves `.loaded` / `.empty` via `resolveInitialSnapshot(rowCount:)`.
    func loadFirstPage() async {
        loadState = .loading(slow: false)
        startSlowHint()
        defer { cancelSlowHint() }
        do {
            let next = try await withTimeout(hardCapTimeout) { [self] in
                try await fetchFeedOperation(nextPageCursor)
            }
            nextPageCursor = next
            if next == nil { feedExhausted = true }
            hasCompletedInitialFetch = true
        } catch {
            let failure = LoadFailure.classify(error, isOnline: reachabilityMonitor.isOnline)
            lastFailureDiagnostics = failure.diagnostics
            loadState = .failed(failure)
        }
    }

    /// Resolve the initial load once GRDB delivers the first snapshot. No-op if
    /// we've already left the loading state (failed/loaded/empty).
    func resolveInitialSnapshot(rowCount: Int) {
        guard case .loading = loadState else { return }
        if rowCount > 0 {
            loadState = .loaded
        } else if hasCompletedInitialFetch {
            loadState = .empty
        }
        // rowCount == 0 and no fetch yet: a cached-but-empty feed. The controller
        // kicks loadFirstPage(); we stay in .loading until it resolves.
    }

    /// Dismisses the current failure and shows the empty state for this feed.
    /// Backs the error state's "Work offline" action.
    func dismissToEmpty() {
        loadState = .empty
    }

    private func startSlowHint() {
        slowHintTask?.cancel()
        slowHintTask = Task { [weak self, slowThreshold] in
            try? await Task.sleep(for: slowThreshold)
            guard let self, !Task.isCancelled else { return }
            if case .loading = loadState {
                loadState = .loading(slow: true)
            }
        }
    }

    private func cancelSlowHint() {
        slowHintTask?.cancel()
        slowHintTask = nil
    }

    // MARK: - Pagination

    func didScrollToBottom() {
        Task { await loadMore() }
    }

    func loadMore() async {
        guard loadState == .loaded, paginationState != .loading, !feedExhausted else { return }
        paginationState = .loading
        await performPagination()
    }

    func retryPagination() async {
        guard paginationState == .failed else { return }
        paginationState = .loading
        await performPagination()
    }

    private func performPagination() async {
        do {
            let next = try await withTimeout(hardCapTimeout) { [self] in
                try await fetchFeedOperation(nextPageCursor)
            }
            nextPageCursor = next
            if next == nil { feedExhausted = true }
            paginationState = .idle
        } catch {
            let failure = LoadFailure.classify(error, isOnline: reachabilityMonitor.isOnline)
            lastFailureDiagnostics = failure.diagnostics
            logger.error("Pagination fetch failed: \(failure.diagnostics, privacy: .public)")
            paginationState = .failed
        }
    }

    // MARK: - Host / empty / title (unchanged behavior)

    var instanceHost: String? {
        switch feed.feedType {
        case let .community(_, instance, _):
            return instance.host
        case .frontpage, .saved:
            return accountScope.instanceActorId?.host
        }
    }

    struct EmptyState {
        let symbolName: String
        let title: String
        let message: String
    }

    var emptyState: EmptyState {
        switch feed.feedType {
        case .saved:
            return EmptyState(
                symbolName: "bookmark",
                title: NSLocalizedString("No saved posts yet", comment: "Empty-state title for the saved-posts feed"),
                message: NSLocalizedString("Posts you save will show up here.", comment: "Empty-state message for the saved-posts feed")
            )
        case .frontpage, .community:
            return EmptyState(
                symbolName: "tray",
                title: NSLocalizedString("No posts", comment: "Empty-state title for a post feed"),
                message: NSLocalizedString("There are no posts to show here.", comment: "Empty-state message for a post feed")
            )
        }
    }

    private static func navigationTitle(for feedType: FeedType) -> String {
        switch feedType {
        case let .frontpage(listingType, _):
            switch listingType {
            case .All: return "All"
            case .Local: return "Local"
            case .Subscribed: return "Subscribed"
            case .ModeratorView: return "Moderator view"
            }
        case let .community(communityName, instance, _):
            return "\(communityName)@\(instance.hostWithPort)"
        case .saved:
            return NSLocalizedString("Saved", comment: "Navigation title for the saved-posts feed")
        }
    }
}
