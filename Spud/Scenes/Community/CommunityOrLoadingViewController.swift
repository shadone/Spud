//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import OSLog
import SpudDataKit
import SpudUIKit
import SpudUtilKit
import UIKit

private let logger = Logger.app

/// Entry point for the community screen. Resolves the community's server-side
/// id (fetching it by name when not yet cached) and then swaps in the content
/// `CommunityViewController`, which hosts the header above the post feed.
class CommunityOrLoadingViewController: UIViewController {
    typealias OwnDependencies =
        HasAccountService &
        HasAlertService &
        HasAppDatabase
    typealias NestedDependencies =
        CommunityViewController.Dependencies
    typealias Dependencies = NestedDependencies & OwnDependencies

    /// Note: `CommunityViewController.Dependencies` is spelled out as a concrete
    /// protocol composition (see that type), so this typealias does not form a
    /// recursive cycle back through PostList/PostDetail.
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    var accountService: AccountServiceType {
        dependencies.own.accountService
    }

    private var accountScope: AccountScope {
        dependencies.own.accountService.scope(forAccountKeychainId: accountKeychainId)
    }

    var alertService: AlertServiceType {
        dependencies.own.alertService
    }

    var appDatabase: AppDatabase {
        dependencies.own.appDatabase
    }

    // MARK: Private

    private let communityName: String
    private let instance: InstanceActorId
    private let accountKeychainId: String

    private var currentViewController: UIViewController?
    private var loadTask: Task<Void, Never>?

    private lazy var loadingIndicator: UIActivityIndicatorView = {
        let view = UIActivityIndicatorView(style: .medium)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    // MARK: Functions

    init(
        communityName: String,
        instance: InstanceActorId,
        accountKeychainId: String,
        dependencies: Dependencies
    ) {
        self.dependencies = (own: dependencies, nested: dependencies)
        self.communityName = communityName
        self.instance = instance
        self.accountKeychainId = accountKeychainId

        super.init(nibName: nil, bundle: nil)

        navigationItem.title = "!\(communityName)"
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background

        view.addSubview(loadingIndicator)
        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        loadingIndicator.startAnimating()

        loadTask?.cancel()
        loadTask = Task { @MainActor [weak self] in
            await self?.loadAndShow()
        }
    }

    /// Resolves the fully-qualified community name to query Lemmy with. A bare
    /// local name resolves on the home instance; a remote community is queried
    /// fully-qualified so any instance resolves it.
    private var qualifiedName: String {
        "\(communityName)@\(instance.hostWithPort)"
    }

    private func loadAndShow() async {
        let lemmyService = accountScope.lemmyService
        let serverCommunityId: Components.Schemas.CommunityID
        do {
            serverCommunityId = try await lemmyService.fetchCommunityInfo(communityName: qualifiedName)
        } catch {
            alertService.handle(error, for: .fetchCommunityInfo)
            loadingIndicator.stopAnimating()
            return
        }

        if Task.isCancelled { return }

        guard let accountRowId = appDatabase.accountRowIdSync(forKeychainId: accountKeychainId) else {
            logger.error("No account row id for keychainId when showing community")
            loadingIndicator.stopAnimating()
            return
        }

        let feed = accountService.createFeed(
            forAccountKeychainId: accountKeychainId,
            feedType: .community(
                communityName: communityName,
                instance: instance,
                sortType: accountService.defaultSortType(forAccountKeychainId: accountKeychainId)
            )
        )

        let contentVC = CommunityViewController(
            accountRowId: accountRowId,
            serverCommunityId: serverCommunityId,
            feed: feed,
            accountKeychainId: accountKeychainId,
            dependencies: dependencies.nested
        )

        loadingIndicator.stopAnimating()
        show(contentVC)
    }

    private func show(_ viewController: UIViewController) {
        remove(child: currentViewController)
        currentViewController = viewController

        add(child: viewController)
        addSubviewWithEdgeConstraints(child: viewController)
    }
}
