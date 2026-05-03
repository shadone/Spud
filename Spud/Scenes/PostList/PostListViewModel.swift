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

private let logger = Logger.app

/// View-model state for PostListViewController. Holds plain values driven by
/// GRDB observations (rows) and legacy fetch calls (paging). Sort-type and
/// reload still construct a fresh `LemmyFeed` via the legacy data service —
/// that part of the pipeline migrates in Stage 7.
@MainActor
@Observable
final class PostListViewModel {
    typealias OwnDependencies =
        HasAccountService &
        HasAlertService
    typealias Dependencies = OwnDependencies

    @ObservationIgnored
    private let dependencies: OwnDependencies

    var feed: LemmyFeed
    let account: LemmyAccount
    var navigationTitle: String
    var isFetchingNextPage: Bool = false

    private var accountService: AccountServiceType {
        dependencies.accountService
    }

    private var alertService: AlertServiceType {
        dependencies.alertService
    }

    init(feed: LemmyFeed, dependencies: Dependencies) {
        self.dependencies = dependencies
        self.feed = feed
        account = feed.account
        navigationTitle = Self.navigationTitle(for: feed)
    }

    func didChangeSortType(_ sortType: Components.Schemas.SortType) {
        let newFeed = accountService
            .lemmyDataService(for: account)
            .createFeed(duplicateOf: feed, sortType: sortType)
        feed = newFeed
        navigationTitle = Self.navigationTitle(for: newFeed)
    }

    func didClickReload() {
        let newFeed = accountService
            .lemmyDataService(for: account)
            .createFeed(duplicateOf: feed)
        feed = newFeed
        navigationTitle = Self.navigationTitle(for: newFeed)
    }

    func didScrollToBottom() {
        guard !isFetchingNextPage else { return }
        Task { await fetchNextPage() }
    }

    /// Called once after the controller has wired up the GRDB observation. If
    /// the feed has no rows yet, kick a fetch from the server.
    func didPrepareObservation(numberOfFetchedPosts: Int) {
        guard numberOfFetchedPosts == 0 else { return }
        Task { await fetchNextPage() }
    }

    func fetchNextPage() async {
        assert(feed.pages.count + 1 < Int64.max)
        let nextPageNumber = Int64(feed.pages.count + 1)

        isFetchingNextPage = true
        defer { isFetchingNextPage = false }

        do {
            try await accountService
                .lemmyService(for: account)
                .fetchFeed(feedId: feed.objectID, page: nextPageNumber)
        } catch {
            alertService.handle(error, for: .fetchPostList)
        }
    }

    private static func navigationTitle(for feed: LemmyFeed) -> String {
        switch feed.feedType {
        case let .frontpage(listingType, _):
            switch listingType {
            case .All: return "All"
            case .Local: return "Local"
            case .Subscribed: return "Subscribed"
            case .ModeratorView: return "Moderator view"
            }
        case let .community(communityName, instance, _):
            return "\(communityName)@\(instance.hostWithPort)"
        }
    }
}
