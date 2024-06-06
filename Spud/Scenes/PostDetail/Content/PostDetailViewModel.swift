//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import CoreData
import LemmyKit
import SpudDataKit

@MainActor
protocol PostDetailViewModelInputs {
//    func voteOnPost(_ action: VoteStatus.Action)
//    func voteOnComment(_ comment: RedditComment, _ action: VoteStatus.Action)
    func didChangeCommentSortType(_ sortType: Components.Schemas.CommentSortType)
    func didPrepareFetchController(numberOfFetchedComments: Int)
}

@MainActor
protocol PostDetailViewModelOutputs {
    var postInfo: LemmyPostInfo { get }
    var headerViewModel: PostDetailHeaderViewModel { get }
    var commentSortType: CurrentValueSubject<Components.Schemas.CommentSortType, Never> { get }
}

@MainActor
protocol PostDetailViewModelType {
    var inputs: PostDetailViewModelInputs { get }
    var outputs: PostDetailViewModelOutputs { get }
}

@MainActor
class PostDetailViewModel: PostDetailViewModelType, PostDetailViewModelInputs, PostDetailViewModelOutputs {
    typealias OwnDependencies =
        HasAccountService &
        HasAlertService &
        HasPreferencesService
    typealias NestedDependencies =
        PostDetailHeaderViewModel.Dependencies
    typealias Dependencies = NestedDependencies & OwnDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    var accountService: AccountServiceType { dependencies.own.accountService }
    var alertService: AlertServiceType { dependencies.own.alertService }

    // MARK: Private

    let postObjectId: NSManagedObjectID

    private var disposables = Set<AnyCancellable>()

    // MARK: Functions

    init(
        postInfo: LemmyPostInfo,
        dependencies: Dependencies
    ) {
        self.dependencies = (own: dependencies, nested: dependencies)
        self.postInfo = postInfo

        postObjectId = postInfo.post.objectID

        headerViewModel = PostDetailHeaderViewModel(
            postInfo: postInfo,
            dependencies: dependencies
        )

        let preferencesService = dependencies.preferencesService
        commentSortType = CurrentValueSubject(preferencesService.defaultCommentSortType)
    }

    // MARK: Type

    var inputs: PostDetailViewModelInputs { self }
    var outputs: PostDetailViewModelOutputs { self }

    // MARK: Outputs

    let postInfo: LemmyPostInfo
    let headerViewModel: PostDetailHeaderViewModel
    let commentSortType: CurrentValueSubject<Components.Schemas.CommentSortType, Never>

    // MARK: Inputs

//    func voteOnPost(_ action: VoteStatus.Action) {
//        accountService
//            .redditService(for: post.account)?
//            .vote(postId: postObjectId, vote: action)
//            .sink(receiveCompletion: { _ in
//            }) { _ in
//            }
//            .store(in: &disposables)
//    }
//
//    func voteOnComment(_ comment: RedditComment, _ action: VoteStatus.Action) {
//        accountService
//            .redditService(for: post.account)?
//            .vote(commentId: comment.objectID, vote: action)
//            .sink(receiveCompletion: { _ in
//            }) { _ in
//            }
//            .store(in: &disposables)
//    }

    func didChangeCommentSortType(_ sortType: Components.Schemas.CommentSortType) {
        commentSortType.send(sortType)
    }

    func didPrepareFetchController(numberOfFetchedComments: Int) {
        Task {
            await fetchComments()
        }
    }

    private func fetchComments() async {
        do {
            try await accountService
                .lemmyService(for: postInfo.post.account)
                .fetchComments(postId: postObjectId, sortType: commentSortType.value)
        } catch {
            alertService.handle(error, for: .fetchComments)
        }
    }
}
