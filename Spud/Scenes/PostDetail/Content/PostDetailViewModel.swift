//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import CoreData
import LemmyKit
import SpudDataKit

protocol PostDetailViewModelInputs {
//    func voteOnPost(_ action: VoteStatus.Action)
//    func voteOnComment(_ comment: RedditComment, _ action: VoteStatus.Action)
    func didChangeCommentSortType(_ sortType: CommentSortType)
    func didPrepareFetchController(numberOfFetchedComments: Int)
}

protocol PostDetailViewModelOutputs {
    var postInfo: LemmyPostInfo { get }
    var headerViewModel: PostDetailHeaderViewModel { get }
    var commentSortType: CurrentValueSubject<CommentSortType, Never> { get }
}

protocol PostDetailViewModelType {
    var inputs: PostDetailViewModelInputs { get }
    var outputs: PostDetailViewModelOutputs { get }
}

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
    let commentSortType: CurrentValueSubject<CommentSortType, Never>

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

    func didChangeCommentSortType(_ sortType: CommentSortType) {
        commentSortType.send(sortType)
    }

    func didPrepareFetchController(numberOfFetchedComments: Int) {
        accountService
            .lemmyService(for: postInfo.post.account)
            .fetchComments(postId: postObjectId, sortType: commentSortType.value)
            .sink(
                receiveCompletion: alertService.errorHandler(for: .fetchComments),
                receiveValue: { _ in }
            )
            .store(in: &disposables)
    }
}
