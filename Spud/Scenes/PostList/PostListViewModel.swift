//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import Foundation
import LemmyKit
import OSLog
import SpudDataKit

@MainActor
protocol PostListViewModelInputs {
    func didSelectPost(_ post: LemmyPost?)
    func didChangeSelectedPostIndex(_ index: Int?)
    func didChangeNumberOfPosts(inserted: Int)
    func didChangeSortType(_ sortType: Components.Schemas.SortType)
    func didClickReload()
    func didScrollToBottom()
    func didPrepareFetchController(numberOfFetchedPosts: Int)
}

@MainActor
protocol PostListViewModelOutputs {
    var feed: CurrentValueSubject<LemmyFeed, Never> { get }
    var account: LemmyAccount { get }
    var selectedPost: CurrentValueSubject<LemmyPost?, Never> { get }
    var selectedPostIndex: CurrentValueSubject<Int?, Never> { get }
    var numberOfPosts: CurrentValueSubject<Int, Never> { get }
    var isFetchingNextPage: CurrentValueSubject<Bool, Never> { get }
    /// The name of this feed to be put in the navigation bar.
    var navigationTitle: AnyPublisher<String, Never> { get }
}

@MainActor
protocol PostListViewModelType {
    var inputs: PostListViewModelInputs { get }
    var outputs: PostListViewModelOutputs { get }
}

@MainActor
class PostListViewModel: PostListViewModelType, PostListViewModelInputs, PostListViewModelOutputs {
    typealias OwnDependencies =
        HasAccountService &
        HasAlertService
    typealias NestedDependencies =
        PostDetailViewController.Dependencies &
        PostListPostViewModel.Dependencies
    typealias Dependencies = NestedDependencies & OwnDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    var accountService: AccountServiceType { dependencies.own.accountService }
    var alertService: AlertServiceType { dependencies.own.alertService }

    // MARK: Private

    private var disposables = Set<AnyCancellable>()

    // MARK: Functions

    init(
        feed: LemmyFeed,
        dependencies: Dependencies
    ) {
        self.dependencies = (own: dependencies, nested: dependencies)

        account = feed.account
        self.feed = CurrentValueSubject<LemmyFeed, Never>(feed)

        navigationTitle = self.feed
            .map { feed in
                switch feed.feedType {
                case let .frontpage(listingType, _):
                    switch listingType {
                    case .All:
                        return "All"
                    case .Local:
                        return "Local"
                    case .Subscribed:
                        return "Subscribed"
                    case .ModeratorView:
                        return "Moderator view"
                    }

                case let .community(communityName, instance, _):
                    return "\(communityName)@\(instance.hostWithPort)"
                }
            }
            .eraseToAnyPublisher()
    }

    func fetchNextPage() async {
        // TODO: this seems bad, wouldn't this causes a fault on "pages"
        //       and suddenly fetch all pages from this feed into memory?
        assert(feed.value.pages.count + 1 < Int64.max)
        let nextPageNumber = Int64(feed.value.pages.count + 1)

        isFetchingNextPage.send(true)
        do {
            try await accountService
                .lemmyService(for: account)
                .fetchFeed(feedId: feed.value.objectID, page: nextPageNumber)
        } catch {
            alertService.handle(error, for: .fetchPostList)
        }

        isFetchingNextPage.send(false)
    }

    // MARK: Type

    var inputs: PostListViewModelInputs { self }
    var outputs: PostListViewModelOutputs { self }

    // MARK: Outputs

    let feed: CurrentValueSubject<LemmyFeed, Never>
    let account: LemmyAccount
    let selectedPost = CurrentValueSubject<LemmyPost?, Never>(nil)
    let selectedPostIndex = CurrentValueSubject<Int?, Never>(nil)
    let numberOfPosts = CurrentValueSubject<Int, Never>(0)
    let isFetchingNextPage = CurrentValueSubject<Bool, Never>(false)
    let navigationTitle: AnyPublisher<String, Never>

    // MARK: Inputs

    func didSelectPost(_ post: LemmyPost?) {
        selectedPost.send(post)
    }

    func didChangeSelectedPostIndex(_ index: Int?) {
        selectedPostIndex.send(index)
    }

    func didChangeNumberOfPosts(inserted: Int) {
        numberOfPosts.send(numberOfPosts.value + inserted)
    }

    func didChangeSortType(_ sortType: Components.Schemas.SortType) {
        let newFeed = accountService
            .lemmyDataService(for: account)
            .createFeed(duplicateOf: feed.value, sortType: sortType)
        feed.send(newFeed)
    }

    func didClickReload() {
        let newFeed = accountService
            .lemmyDataService(for: account)
            .createFeed(duplicateOf: feed.value)
        feed.send(newFeed)
    }

    func didScrollToBottom() {
        guard !isFetchingNextPage.value else {
            return
        }
        Task {
            await fetchNextPage()
        }
    }

    func didPrepareFetchController(numberOfFetchedPosts: Int) {
        // if we already have posts lets use that and not trigger a new fetch from server.
        guard numberOfFetchedPosts == 0 else { return }
        Task {
            await fetchNextPage()
        }
    }
}
