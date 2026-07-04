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

    /// `true` while this controller is the empty placeholder shown in the
    /// split view's secondary column before any post is selected. Used by the
    /// split-view collapse handoff to avoid carrying the placeholder over into
    /// the compact navigation stack.
    var isEmptyPlaceholder: Bool {
        if case .empty = state { return true }
        return false
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
        case unavailable(reason: PostUnavailableReason)
    }

    private var state: State {
        didSet {
            stateChanged()
        }
    }

    private let accountKeychainId: String
    private var currentViewController: UIViewController?
    /// A `/comment/<id>` permalink target to scroll to once the post detail is
    /// shown. Consumed (set to nil) the first time a content controller is built,
    /// so an iPad detail-column reuse with a different post doesn't reuse it.
    private var scrollToCommentId: Components.Schemas.CommentID?

    // MARK: - Functions

    init(
        serverPostId: Components.Schemas.PostID,
        accountKeychainId: String,
        scrollToCommentId: Components.Schemas.CommentID? = nil,
        dependencies: Dependencies
    ) {
        self.dependencies = (own: dependencies, nested: dependencies)
        self.accountKeychainId = accountKeychainId
        self.scrollToCommentId = scrollToCommentId

        let resolved = Self.resolveState(
            forServerPostId: serverPostId,
            accountKeychainId: accountKeychainId,
            appDatabase: dependencies.appDatabase
        )
        state = resolved

        super.init(nibName: nil, bundle: nil)

        stateChanged()
    }

    init(accountKeychainId: String, dependencies: Dependencies) {
        self.dependencies = (own: dependencies, nested: dependencies)
        self.accountKeychainId = accountKeychainId

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
            accountKeychainId: accountKeychainId,
            appDatabase: appDatabase
        )
    }

    private static func resolveState(
        forServerPostId serverPostId: Components.Schemas.PostID,
        accountKeychainId: String,
        appDatabase: AppDatabase
    ) -> State {
        if appDatabase.postRowIdSync(
            forKeychainId: accountKeychainId,
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
                accountKeychainId: accountKeychainId,
                scrollToCommentId: scrollToCommentId,
                dependencies: dependencies.nested
            )
            // One-shot: don't re-anchor on a later post selected into this column.
            scrollToCommentId = nil
            newViewController = contentViewController

            // FIXME: this is hacky, make custom ChildVC base class for handling navitems
            navigationItem.rightBarButtonItem = contentViewController.navigationItem.rightBarButtonItem

            contentViewController.didBecomeUnavailable = { [weak self] reason in
                self?.state = .unavailable(reason: reason)
            }

        case let .load(serverPostId):
            let loadingViewController = PostDetailLoadingViewController(
                serverPostId: serverPostId,
                accountKeychainId: accountKeychainId,
                dependencies: dependencies.nested
            )
            newViewController = loadingViewController

            loadingViewController.didFinishLoading = { [weak self] serverPostId in
                self?.state = .post(serverPostId: serverPostId)
            }
            loadingViewController.didFail = { [weak self] reason in
                self?.state = .unavailable(reason: reason)
            }

        case let .unavailable(reason):
            newViewController = PostUnavailableViewController(reason: reason)
        }

        add(child: newViewController)
        addSubviewWithEdgeConstraints(child: newViewController)
    }
}
