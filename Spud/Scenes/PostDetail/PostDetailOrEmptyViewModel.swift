//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import LemmyKit
import SpudDataKit
import UIKit

enum PostDetailOrEmpty {
    enum ViewState {
        case empty
        case loading
        case displayingPost
    }
}

protocol PostDetailOrEmptyViewModelInputs {
    func startLoadingPost(postId: PostId)
    func didFinishLoadingPostInfo(_ postInfo: LemmyPostInfo)
    func displayPostInfo(_ postInfo: LemmyPostInfo)
    func displayEmpty()
}

protocol PostDetailOrEmptyViewModelOutputs {
    var currentPostInfo: AnyPublisher<LemmyPostInfo?, Never> { get }
    var loadingPostInfo: AnyPublisher<PostId, Never> { get }
    var postInfoLoaded: AnyPublisher<LemmyPostInfo, Never> { get }
    var viewState: AnyPublisher<PostDetailOrEmpty.ViewState, Never> { get }
}

protocol PostDetailOrEmptyViewModelType {
    var inputs: PostDetailOrEmptyViewModelInputs { get }
    var outputs: PostDetailOrEmptyViewModelOutputs { get }
}

class PostDetailOrEmptyViewModel:
    PostDetailOrEmptyViewModelType,
    PostDetailOrEmptyViewModelInputs,
    PostDetailOrEmptyViewModelOutputs
{
    private let currentlyDisplayedPostInfo: CurrentValueSubject<LemmyPostInfo?, Never>
    private let viewStateSubject: CurrentValueSubject<PostDetailOrEmpty.ViewState, Never>
    private var disposables = Set<AnyCancellable>()

    init(_ initialPostInfo: LemmyPostInfo?) {
        currentlyDisplayedPostInfo = CurrentValueSubject<LemmyPostInfo?, Never>(initialPostInfo)

        postInfoLoaded = didFinishLoadingPostInfoSubject
            .ignoreNil()
            .eraseToAnyPublisher()

        currentPostInfo = currentlyDisplayedPostInfo
            .eraseToAnyPublisher()

        viewStateSubject = CurrentValueSubject(initialPostInfo == nil ? .empty : .displayingPost)
        viewState = viewStateSubject
            .eraseToAnyPublisher()

        loadingPostInfo = startLoadingPostSubject
            .eraseToAnyPublisher()

        didFinishLoadingPostInfoSubject
            .sink { [weak self] postInfo in
                self?.currentlyDisplayedPostInfo.send(postInfo)
            }
            .store(in: &disposables)

        displayPostInfoSubject
            .sink { [weak self] postInfo in
                self?.currentlyDisplayedPostInfo.send(postInfo)
            }
            .store(in: &disposables)

        displayEmptySubject
            .sink { [weak self] _ in
                self?.viewStateSubject.send(.empty)
                self?.currentlyDisplayedPostInfo.send(nil)
            }
            .store(in: &disposables)
    }

    // MARK: Type

    var inputs: PostDetailOrEmptyViewModelInputs { self }
    var outputs: PostDetailOrEmptyViewModelOutputs { self }

    // MARK: Outputs

    let currentPostInfo: AnyPublisher<LemmyPostInfo?, Never>
    let loadingPostInfo: AnyPublisher<PostId, Never>
    let postInfoLoaded: AnyPublisher<LemmyPostInfo, Never>
    let viewState: AnyPublisher<PostDetailOrEmpty.ViewState, Never>

    // MARK: Inputs

    private let startLoadingPostSubject = PassthroughSubject<PostId, Never>()
    func startLoadingPost(postId: PostId) {
        startLoadingPostSubject.send(postId)
    }

    private let didFinishLoadingPostInfoSubject = PassthroughSubject<LemmyPostInfo?, Never>()
    func didFinishLoadingPostInfo(_ postInfo: LemmyPostInfo) {
        didFinishLoadingPostInfoSubject.send(postInfo)
    }

    private let displayPostInfoSubject = PassthroughSubject<LemmyPostInfo?, Never>()
    func displayPostInfo(_ postInfo: LemmyPostInfo) {
        displayPostInfoSubject.send(postInfo)
    }

    private let displayEmptySubject = PassthroughSubject<Void, Never>()
    func displayEmpty() {
        displayEmptySubject.send(())
    }
}
