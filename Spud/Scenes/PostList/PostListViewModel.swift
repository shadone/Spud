//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import Foundation
import os.log
import LemmyKit

protocol PostListViewModelInputs {
    func didSelectPost(_ post: LemmyPost?)
    func didChangeSelectedPostIndex(_ index: Int?)
    func didChangeNumberOfPosts(inserted: Int)
    func didChangeSortType(_ sortType: SortType)
    func didClickReload()
    func didScrollToBottom()
    func didPrepareFetchController()
}

protocol PostListViewModelOutputs {
    var feed: CurrentValueSubject<LemmyFeed, Never> { get }
    var selectedPost: CurrentValueSubject<LemmyPost?, Never> { get }
    var selectedPostIndex: CurrentValueSubject<Int?, Never> { get }
    var numberOfPosts: CurrentValueSubject<Int, Never> { get }
    var sortType: AnyPublisher<SortType, Never> { get }
    var isFetchingNextPage: CurrentValueSubject<Bool, Never> { get }
}

protocol PostListViewModelType {
    var inputs: PostListViewModelInputs { get }
    var outputs: PostListViewModelOutputs { get }
}

class PostListViewModel: PostListViewModelType, PostListViewModelInputs, PostListViewModelOutputs {
    private let account: LemmyAccount
    private let accountService: AccountServiceType
    private var disposables = Set<AnyCancellable>()

    init(
        feed: LemmyFeed,
        accountService: AccountServiceType
    ) {
        account = feed.account
        self.accountService = accountService
        self.feed = CurrentValueSubject<LemmyFeed, Never>(feed)

        sortType = self.feed
            .map { feed in
                switch feed.feedType {
                case let .frontpage(_, sortType):
                    return sortType
                }
            }
            .eraseToAnyPublisher()
    }

    func fetchNextPage() {
        // TODO: this seems bad, wouldn't this causes a fault on "pages"
        //       and suddenly fetch all pages from this feed into memory?
        let nextPageNumber = feed.value.pages.count + 1

        isFetchingNextPage.send(true)
        accountService
            .lemmyService(for: account)
            .fetchFeed(feedId: feed.value.objectID, page: nextPageNumber)
            // Explicitly specify RunLoop.main is required to ensure early delivery.
            // Without it the completion is not triggered while scroll view is
            // scrolling, instead the completion is delayed until scrolling finishes.
            .receive(on: RunLoop.main)
            .sink(receiveCompletion: { [weak self] _ in
                self?.isFetchingNextPage.send(false)
            }) { _ in }
            .store(in: &disposables)
    }

    // MARK: Type

    var inputs: PostListViewModelInputs { self }
    var outputs: PostListViewModelOutputs { self }

    // MARK: Outputs

    let feed: CurrentValueSubject<LemmyFeed, Never>
    let selectedPost = CurrentValueSubject<LemmyPost?, Never>(nil)
    let selectedPostIndex = CurrentValueSubject<Int?, Never>(nil)
    let numberOfPosts = CurrentValueSubject<Int, Never>(0)
    let sortType: AnyPublisher<SortType, Never>
    let isFetchingNextPage = CurrentValueSubject<Bool, Never>(false)

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

    func didChangeSortType(_ sortType: SortType) {
        let lemmyService = accountService.lemmyService(for: account)
        let newFeed = lemmyService.createFeed(duplicateOf: feed.value, sortType: sortType)
        feed.send(newFeed)
    }

    func didClickReload() {
        let lemmyService = accountService.lemmyService(for: account)
        let newFeed = lemmyService.createFeed(duplicateOf: feed.value)
        feed.send(newFeed)
    }

    func didScrollToBottom() {
        guard !isFetchingNextPage.value else {
            return
        }
        fetchNextPage()
    }

    func didPrepareFetchController() {
        fetchNextPage()
    }
}
