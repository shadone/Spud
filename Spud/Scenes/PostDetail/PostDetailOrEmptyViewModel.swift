//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import UIKit

enum PostDetailOrEmpty {
    enum ViewState {
        case empty
        case loading
        case displayingPost
    }
}

protocol PostDetailOrEmptyViewModelInputs {
    func startLoadingPost(postId: LemmyPost.PostId)
    func didFinishLoadingPost(_ post: LemmyPost)
    func displayPost(_ post: LemmyPost)
    func displayEmpty()
}

protocol PostDetailOrEmptyViewModelOutputs {
    var currentPost: AnyPublisher<LemmyPost?, Never> { get }
    var loadPostById: AnyPublisher<LemmyPost.PostId, Never> { get }
    var postLoaded: AnyPublisher<LemmyPost, Never> { get }
    var viewState: AnyPublisher<PostDetailOrEmpty.ViewState, Never> { get }
}

protocol PostDetailOrEmptyViewModelType {
    var inputs: PostDetailOrEmptyViewModelInputs { get }
    var outputs: PostDetailOrEmptyViewModelOutputs { get }
}

class PostDetailOrEmptyViewModel: PostDetailOrEmptyViewModelType, PostDetailOrEmptyViewModelInputs, PostDetailOrEmptyViewModelOutputs {
    private let currentlyDisplayedPost: CurrentValueSubject<LemmyPost?, Never>
    private let viewStateSubject: CurrentValueSubject<PostDetailOrEmpty.ViewState, Never>
    private var disposables = Set<AnyCancellable>()

    init(_ initialPost: LemmyPost?) {
        currentlyDisplayedPost = CurrentValueSubject<LemmyPost?, Never>(initialPost)

        postLoaded = currentlyDisplayedPost
            .ignoreNil()
            .eraseToAnyPublisher()

        currentPost = currentlyDisplayedPost
            .eraseToAnyPublisher()

        viewStateSubject = CurrentValueSubject(initialPost == nil ? .empty : .displayingPost)
        viewState = viewStateSubject
            .eraseToAnyPublisher()

        loadPostById = startLoadingPostSubject
            .ignoreNil()
            .eraseToAnyPublisher()

        didFinishLoadingPostSubject
            .sink { [weak self] post in
                self?.currentlyDisplayedPost.send(post)
            }
            .store(in: &disposables)

        displayPostSubject
            .sink { [weak self] post in
                self?.currentlyDisplayedPost.send(post)
            }
            .store(in: &disposables)

        displayEmptySubject
            .sink { [weak self] _ in
                self?.viewStateSubject.send(.empty)
                self?.currentlyDisplayedPost.send(nil)
            }
            .store(in: &disposables)
    }

    // MARK: Type

    var inputs: PostDetailOrEmptyViewModelInputs { self }
    var outputs: PostDetailOrEmptyViewModelOutputs { self }

    // MARK: Outputs

    let currentPost: AnyPublisher<LemmyPost?, Never>
    let loadPostById: AnyPublisher<LemmyPost.PostId, Never>
    let postLoaded: AnyPublisher<LemmyPost, Never>
    let viewState: AnyPublisher<PostDetailOrEmpty.ViewState, Never>

    // MARK: Inputs

    private let startLoadingPostSubject = PassthroughSubject<LemmyPost.PostId?, Never>()
    func startLoadingPost(postId: LemmyPost.PostId) {
        startLoadingPostSubject.send(postId)
    }

    private let didFinishLoadingPostSubject = PassthroughSubject<LemmyPost?, Never>()
    func didFinishLoadingPost(_ post: LemmyPost) {
        didFinishLoadingPostSubject.send(post)
    }

    private let displayPostSubject = PassthroughSubject<LemmyPost?, Never>()
    func displayPost(_ post: LemmyPost) {
        displayPostSubject.send(post)
    }

    private let displayEmptySubject = PassthroughSubject<Void, Never>()
    func displayEmpty() {
        displayEmptySubject.send(())
    }
}
