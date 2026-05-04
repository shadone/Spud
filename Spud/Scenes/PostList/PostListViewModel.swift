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

/// View-model state for PostListViewController. Holds a `FeedHandle`
/// (feedKey + feedType) plus plain values driven by GRDB observations and
/// LemmyService fetches. Pagination is cursor-based — `nextPageCursor`
/// comes from the previous fetch's response and is nil at the head of the
/// feed and after exhaustion.
@MainActor
@Observable
final class PostListViewModel {
    typealias OwnDependencies =
        HasAccountService &
        HasAlertService
    typealias Dependencies = OwnDependencies

    @ObservationIgnored
    private let dependencies: OwnDependencies

    var feed: FeedHandle
    let accountKeychainId: String
    var navigationTitle: String
    var isFetchingNextPage: Bool = false

    @ObservationIgnored
    private var nextPageCursor: String?
    @ObservationIgnored
    private var feedExhausted: Bool = false

    private var accountService: AccountServiceType {
        dependencies.accountService
    }

    private var alertService: AlertServiceType {
        dependencies.alertService
    }

    init(feed: FeedHandle, accountKeychainId: String, dependencies: Dependencies) {
        self.dependencies = dependencies
        self.feed = feed
        self.accountKeychainId = accountKeychainId
        navigationTitle = Self.navigationTitle(for: feed.feedType)
    }

    func didChangeSortType(_ sortType: Components.Schemas.SortType) {
        let newFeed = accountService.createFeed(
            duplicateOf: feed,
            forAccountKeychainId: accountKeychainId,
            sortType: sortType
        )
        feed = newFeed
        nextPageCursor = nil
        feedExhausted = false
        navigationTitle = Self.navigationTitle(for: newFeed.feedType)
    }

    func didClickReload() {
        let newFeed = accountService.createFeed(
            duplicateOf: feed,
            forAccountKeychainId: accountKeychainId
        )
        feed = newFeed
        nextPageCursor = nil
        feedExhausted = false
        navigationTitle = Self.navigationTitle(for: newFeed.feedType)
    }

    func didScrollToBottom() {
        guard !isFetchingNextPage, !feedExhausted else { return }
        Task { await fetchNextPage() }
    }

    /// Called once after the controller has wired up the GRDB observation. If
    /// the feed has no rows yet, kick a fetch from the server.
    func didPrepareObservation(numberOfFetchedPosts: Int) {
        guard numberOfFetchedPosts == 0 else { return }
        Task { await fetchNextPage() }
    }

    func fetchNextPage() async {
        isFetchingNextPage = true
        defer { isFetchingNextPage = false }

        do {
            let returnedCursor = try await accountService
                .lemmyService(forAccountKeychainId: accountKeychainId)
                .fetchFeed(feed, pageCursor: nextPageCursor)
            nextPageCursor = returnedCursor
            if returnedCursor == nil {
                feedExhausted = true
            }
        } catch {
            alertService.handle(error, for: .fetchPostList)
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
        }
    }
}
