//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import LemmyKit
import SpudDataKit
import UIKit

class PostDetailOrEmptyViewController: UIViewController {
    typealias OwnDependencies =
        HasVoid
    typealias NestedDependencies =
        PostDetailLoadingViewController.Dependencies &
        PostDetailViewController.Dependencies
    typealias Dependencies = NestedDependencies & OwnDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    // MARK: - Public

    var contentViewController: PostDetailViewController? {
        currentViewController as? PostDetailViewController
    }

    var postInfoPublisher: AnyPublisher<LemmyPostInfo?, Never> {
        viewModel.outputs.currentPostInfo
    }

    func displayPostInfo(_ postInfo: LemmyPostInfo) {
        viewModel.inputs.displayPostInfo(postInfo)
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
        case post(LemmyPostInfo)
        case load(postId: PostId)
    }

    private var state: State {
        didSet {
            stateChanged()
        }
    }

    private let account: LemmyAccount
    private var currentViewController: UIViewController?
    private var disposables = Set<AnyCancellable>()

    // MARK: - Functions

    init(postInfo: LemmyPostInfo, dependencies: Dependencies) {
        self.dependencies = (own: dependencies, nested: dependencies)
        account = postInfo.post.account

        state = .post(postInfo)
        viewModel = PostDetailOrEmptyViewModel(postInfo)

        super.init(nibName: nil, bundle: nil)

        bindViewModel()

        stateChanged()
    }

    init(account: LemmyAccount, dependencies: Dependencies) {
        self.dependencies = (own: dependencies, nested: dependencies)
        self.account = account

        state = .empty
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
        viewModel.outputs.postInfoLoaded
            .sink { [weak self] postInfo in
                self?.state = .post(postInfo)
            }
            .store(in: &disposables)

        viewModel.outputs.loadingPostInfo
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
        remove(child: currentViewController)
        currentViewController = nil

        let newViewController: UIViewController
        switch state {
        case .empty:
            let emptyViewController = PostDetailEmptyViewController()
            newViewController = emptyViewController

        case let .post(postInfo):
            let contentViewController = PostDetailViewController(
                postInfo: postInfo,
                dependencies: dependencies.nested
            )
            newViewController = contentViewController

            // FIXME: this is hacky, make custom ChildVC base class for handling navitems
            navigationItem.rightBarButtonItem = contentViewController.navigationItem.rightBarButtonItem

        case let .load(postId):
            let loadingViewController = PostDetailLoadingViewController(
                postId: postId,
                account: account,
                dependencies: dependencies.nested
            )
            newViewController = loadingViewController

            loadingViewController.didFinishLoading = { [weak self] postInfo in
                self?.viewModel.inputs.didFinishLoadingPostInfo(postInfo)
            }
        }

        add(child: newViewController)
        addSubviewWithEdgeConstraints(child: newViewController)
    }
}
