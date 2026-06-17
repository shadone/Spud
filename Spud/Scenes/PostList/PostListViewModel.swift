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
        HasAccountService
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
    var isFetchingNextPage: Bool = false

    /// True after a page fetch threw. Observed by the controller, which shows
    /// the inline error state when the feed is still empty, or a transient
    /// alert when there are already posts on screen (a pagination failure).
    /// Reset at the start of every fetch and on success.
    var fetchFailed: Bool = false

    @ObservationIgnored
    private(set) var lastFetchError: Error?

    @ObservationIgnored
    private var nextPageCursor: String?
    @ObservationIgnored
    private var feedExhausted: Bool = false

    private var accountService: AccountServiceType {
        dependencies.accountService
    }

    init(feed: FeedHandle, accountScope: AccountScope, dependencies: Dependencies) {
        self.dependencies = dependencies
        self.accountScope = accountScope
        self.feed = feed
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

    /// Switches this list to a different feed entirely (e.g. from the
    /// quick-switch drawer). The controller restarts its observation via
    /// `feedChanged()` afterwards.
    func switchFeed(to feedType: FeedType) {
        let newFeed = accountService.createFeed(
            forAccountKeychainId: accountKeychainId,
            feedType: feedType
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
        fetchFailed = false
        defer { isFetchingNextPage = false }

        do {
            let returnedCursor = try await accountScope.lemmyService
                .fetchFeed(feed, pageCursor: nextPageCursor)
            nextPageCursor = returnedCursor
            lastFetchError = nil
            if returnedCursor == nil {
                feedExhausted = true
            }
        } catch {
            // The controller decides how to surface this: the inline error
            // state when the feed is still empty, or an alert when there are
            // already posts on screen.
            lastFetchError = error
            fetchFailed = true
        }
    }

    /// The host of the instance this feed is served from (e.g. `lemmy.world`),
    /// used to name the server in the feed error state. Community feeds carry
    /// the instance directly; frontpage and saved feeds use the account's home
    /// instance.
    var instanceHost: String? {
        switch feed.feedType {
        case let .community(_, instance, _):
            return instance.host
        case .frontpage, .saved:
            return accountService.instanceActorId(forAccountKeychainId: accountKeychainId)?.host
        }
    }

    /// Designed empty-state copy for the current feed. The saved feed gets a
    /// dedicated message; everything else shares a generic one.
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
                message: NSLocalizedString(
                    "Posts you save will show up here.",
                    comment: "Empty-state message for the saved-posts feed"
                )
            )
        case .frontpage, .community:
            return EmptyState(
                symbolName: "tray",
                title: NSLocalizedString("No posts", comment: "Empty-state title for a post feed"),
                message: NSLocalizedString(
                    "There are no posts to show here.",
                    comment: "Empty-state message for a post feed"
                )
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
