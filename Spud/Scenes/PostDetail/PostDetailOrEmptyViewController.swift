//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import SpudDataKit
import SpudUtilKit
import UIKit

class PostDetailOrEmptyViewController: UIViewController {
    typealias OwnDependencies =
        HasAppDatabase
    typealias NestedDependencies =
        PostDetailLoadingViewController.Dependencies &
        PostDetailViewController.Dependencies
    typealias Dependencies = NestedDependencies & OwnDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    private var appDatabase: AppDatabase {
        dependencies.own.appDatabase
    }

    // MARK: - Public

    var contentViewController: PostDetailViewController? {
        currentViewController as? PostDetailViewController
    }

    func display(serverPostId: Components.Schemas.PostID) {
        state = resolveState(forServerPostId: serverPostId)
    }

    func displayEmpty() {
        state = .empty
    }

    // MARK: - Private

    private enum State {
        case empty
        case post(serverPostId: Components.Schemas.PostID)
        case load(serverPostId: Components.Schemas.PostID)
    }

    private var state: State {
        didSet {
            stateChanged()
        }
    }

    private let account: LemmyAccount
    private var currentViewController: UIViewController?

    // MARK: - Functions

    init(
        serverPostId: Components.Schemas.PostID,
        account: LemmyAccount,
        dependencies: Dependencies
    ) {
        self.dependencies = (own: dependencies, nested: dependencies)
        self.account = account

        let resolved = Self.resolveState(
            forServerPostId: serverPostId,
            account: account,
            appDatabase: dependencies.appDatabase
        )
        state = resolved

        super.init(nibName: nil, bundle: nil)

        stateChanged()
    }

    init(account: LemmyAccount, dependencies: Dependencies) {
        self.dependencies = (own: dependencies, nested: dependencies)
        self.account = account

        state = .empty

        super.init(nibName: nil, bundle: nil)

        stateChanged()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func resolveState(forServerPostId serverPostId: Components.Schemas.PostID) -> State {
        Self.resolveState(
            forServerPostId: serverPostId,
            account: account,
            appDatabase: appDatabase
        )
    }

    private static func resolveState(
        forServerPostId serverPostId: Components.Schemas.PostID,
        account: LemmyAccount,
        appDatabase: AppDatabase
    ) -> State {
        if appDatabase.postRowIdSync(
            forKeychainId: account.id,
            serverPostId: Int64(serverPostId)
        ) != nil {
            return .post(serverPostId: serverPostId)
        }
        return .load(serverPostId: serverPostId)
    }

    private func stateChanged() {
        remove(child: currentViewController)
        currentViewController = nil

        let newViewController: UIViewController
        switch state {
        case .empty:
            let emptyViewController = PostDetailEmptyViewController()
            newViewController = emptyViewController

        case let .post(serverPostId):
            let contentViewController = PostDetailViewController(
                serverPostId: serverPostId,
                account: account,
                dependencies: dependencies.nested
            )
            newViewController = contentViewController

            // FIXME: this is hacky, make custom ChildVC base class for handling navitems
            navigationItem.rightBarButtonItem = contentViewController.navigationItem.rightBarButtonItem

        case let .load(serverPostId):
            let loadingViewController = PostDetailLoadingViewController(
                serverPostId: serverPostId,
                account: account,
                dependencies: dependencies.nested
            )
            newViewController = loadingViewController

            loadingViewController.didFinishLoading = { [weak self] serverPostId in
                self?.state = .post(serverPostId: serverPostId)
            }
        }

        add(child: newViewController)
        addSubviewWithEdgeConstraints(child: newViewController)
    }
}
