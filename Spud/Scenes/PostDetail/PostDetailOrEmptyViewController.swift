//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import LemmyKit
import UIKit

class PostDetailOrEmptyViewController: UIViewController {
    typealias OwnDependencies =
        HasVoid
    typealias NestedDependencies =
        PostDetailViewController.Dependencies &
        PostDetailLoadingViewController.Dependencies
    typealias Dependencies = OwnDependencies & NestedDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    // MARK: - Public

    private(set) var contentViewController: PostDetailViewController?

    var postPublisher: AnyPublisher<LemmyPost?, Never> {
        viewModel.outputs.currentPost
    }

    func displayPost(_ post: LemmyPost) {
        viewModel.inputs.displayPost(post)
    }

    func displayEmpty() {
        viewModel.inputs.displayEmpty()
    }

    func startLoadingPost(postId: PostId) {
        viewModel.inputs.startLoadingPost(postId: postId)
    }

    // MARK: - Private

    private let viewModel: PostDetailOrEmptyViewModelType

    private enum State {
        case empty
        case post(LemmyPost)
        case load(postId: PostId)
    }

    private var state: State = .empty {
        didSet {
            stateChanged()
        }
    }

    private let account: LemmyAccount
    private var loadingViewController: PostDetailLoadingViewController?
    private var disposables = Set<AnyCancellable>()

    // MARK: - Functions

    init(post: LemmyPost, dependencies: Dependencies) {
        self.dependencies = (own: dependencies, nested: dependencies)
        account = post.account

        viewModel = PostDetailOrEmptyViewModel(post)

        super.init(nibName: nil, bundle: nil)

        bindViewModel()

        state = .post(post)
        stateChanged()
    }

    init(account: LemmyAccount, dependencies: Dependencies) {
        self.dependencies = (own: dependencies, nested: dependencies)
        self.account = account

        viewModel = PostDetailOrEmptyViewModel(nil)

        super.init(nibName: nil, bundle: nil)

        bindViewModel()

        stateChanged()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func bindViewModel() {
        viewModel.outputs.postLoaded
            .sink { [weak self] post in
                self?.state = .post(post)
            }
            .store(in: &disposables)

        viewModel.outputs.loadPostById
            .sink { [weak self] postId in
                self?.state = .load(postId: postId)
            }
            .store(in: &disposables)

        viewModel.outputs.viewState
            .sink { [weak self] viewState in
                switch viewState {
                case .empty:
                    self?.state = .empty
                case .displayingPost, .loading:
                    // this is handled in other outputs above
                    break
                }
            }
            .store(in: &disposables)
    }

    private func stateChanged() {
        switch state {
        case .empty:
            remove(child: contentViewController)
            remove(child: loadingViewController)
            let emptyViewController = PostDetailEmptyViewController()
            add(child: emptyViewController)
            addSubviewWithEdgeConstraints(child: emptyViewController)

            contentViewController = nil
            loadingViewController = nil

        case let .post(post):
            if let contentViewController {
                contentViewController.setPost(post)
            } else {
                contentViewController = PostDetailViewController(
                    post: post,
                    dependencies: dependencies.nested
                )

                remove(child: loadingViewController)
                add(child: contentViewController)
                addSubviewWithEdgeConstraints(child: contentViewController)

                loadingViewController = nil
            }

        case let .load(postId):
            let loadingViewController = PostDetailLoadingViewController(
                postId: postId,
                account: account,
                dependencies: dependencies.nested
            )
            self.loadingViewController = loadingViewController

            loadingViewController.didFinishLoading = { [weak self] post in
                self?.viewModel.inputs.didFinishLoadingPost(post)
                self?.state = .post(post)
            }

            remove(child: contentViewController)
            add(child: loadingViewController)
            addSubviewWithEdgeConstraints(child: loadingViewController)

            contentViewController = nil
        }
    }
}
