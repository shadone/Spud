//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import CoreData
import LemmyKit

protocol PostDetailViewModelInputs {
//    func voteOnPost(_ action: VoteStatus.Action)
//    func voteOnComment(_ comment: RedditComment, _ action: VoteStatus.Action)
    func didChangeCommentSortType(_ sortType: CommentSortType)
}

protocol PostDetailViewModelOutputs {
    var post: LemmyPost { get }
    var headerViewModel: PostDetailHeaderViewModel { get }
    var commentSortType: CurrentValueSubject<CommentSortType, Never> { get }
}

protocol PostDetailViewModelType {
    var inputs: PostDetailViewModelInputs { get }
    var outputs: PostDetailViewModelOutputs { get }
}

class PostDetailViewModel: PostDetailViewModelType, PostDetailViewModelInputs, PostDetailViewModelOutputs {
    // MARK: Private

    let postObjectId: NSManagedObjectID

    private let accountService: AccountServiceType

    private var disposables = Set<AnyCancellable>()

    // MARK: Functions

    init(
        post: LemmyPost,
        accountService: AccountServiceType
    ) {
        self.accountService = accountService
        self.post = post

        postObjectId = post.objectID

        headerViewModel = PostDetailHeaderViewModel(
            post: self.post
        )

        commentSortType = CurrentValueSubject(.hot)
    }

    // MARK: Type

    var inputs: PostDetailViewModelInputs { self }
    var outputs: PostDetailViewModelOutputs { self }

    // MARK: Outputs

    let post: LemmyPost
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
}
