//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import OSLog
import SpudDataKit
import SpudUIKit
import SwiftUI
import UIKit

private let logger = Logger.app

class SubscriptionsViewController: UIViewController {
    typealias OwnDependencies =
        HasAccountService &
        HasAppDatabase &
        HasMetaCommunityService
    typealias NestedDependencies =
        PostListViewController.Dependencies &
        CommunityOrLoadingViewController.Dependencies &
        CommunityReadingSplitViewController.Dependencies &
        DiscoverViewController.Dependencies
    typealias Dependencies = NestedDependencies & OwnDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    var accountService: AccountServiceType {
        dependencies.own.accountService
    }

    var appDatabase: AppDatabase {
        dependencies.own.appDatabase
    }

    var metaCommunityService: MetaCommunityServiceType {
        dependencies.own.metaCommunityService
    }

    // MARK: Private

    private let accountKeychainId: String
    private let isSignedIn: Bool
    private var viewModel: SubscriptionsViewModel!

    // MARK: Functions

    init(
        accountKeychainId: String,
        isSignedIn: Bool,
        dependencies: Dependencies
    ) {
        self.dependencies = (own: dependencies, nested: dependencies)
        self.accountKeychainId = accountKeychainId
        self.isSignedIn = isSignedIn

        super.init(nibName: nil, bundle: nil)

        let accountRowId = appDatabase.accountRowIdSync(forKeychainId: accountKeychainId)

        // `AccountScope` is a zero-cost facade (no I/O at construction), and the
        // view model's own `guard let accountRowId` short-circuits before either
        // is ever read when there's no persisted account row — so it's simplest
        // to always pass them rather than gate on `accountRowId` here too.
        viewModel = SubscriptionsViewModel(
            accountRowId: accountRowId,
            isSignedIn: isSignedIn,
            appDatabase: appDatabase,
            accountScope: accountService.scope(forAccountKeychainId: accountKeychainId),
            metaCommunityService: metaCommunityService,
            onFeedRequested: { [weak self] item in
                self?.handle(item: item)
            },
            onExploreRequested: { [weak self] in
                self?.showDiscover()
            }
        )

        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        view.backgroundColor = Theme.background

        let contentVC = UIHostingController(rootView: SubscriptionsView(viewModel: self.viewModel))
        add(child: contentVC)
        addSubviewWithEdgeConstraints(child: contentVC)

        setupNavigationChrome()
    }

    /// Search + sort live in UIKit (the nav root), driving the @Observable view
    /// model the SwiftUI list reads from.
    private func setupNavigationChrome() {
        let search = UISearchController(searchResultsController: nil)
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = NSLocalizedString(
            "Search your communities",
            comment: "Communities tab search placeholder"
        )
        navigationItem.searchController = search
        navigationItem.hidesSearchBarWhenScrolling = false

        rebuildSortMenu()
    }

    private func rebuildSortMenu() {
        let alphabetical = UIAction(
            title: NSLocalizedString("Alphabetical", comment: "Communities sort: A to Z"),
            image: UIImage(systemName: "textformat"),
            state: viewModel.sortOrder == .alphabetical ? .on : .off
        ) { [weak self] _ in self?.setSortOrder(.alphabetical) }

        let byInstance = UIAction(
            title: NSLocalizedString("By instance", comment: "Communities sort: grouped by server"),
            image: UIImage(systemName: "server.rack"),
            state: viewModel.sortOrder == .byInstance ? .on : .off
        ) { [weak self] _ in self?.setSortOrder(.byInstance) }

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "line.3.horizontal.decrease.circle"),
            menu: UIMenu(options: .singleSelection, children: [alphabetical, byInstance])
        )
    }

    private func setSortOrder(_ order: SubscriptionsViewModel.SortOrder) {
        viewModel.sortOrder = order
        rebuildSortMenu()
    }

    private func showDiscover() {
        let discoverVC = DiscoverViewController(
            accountKeychainId: accountKeychainId,
            isSignedIn: isSignedIn,
            dependencies: dependencies.nested
        )
        navigationController?.pushViewController(discoverVC, animated: true)
    }

    private func handle(item: SubscriptionsViewItemType) {
        switch item {
        case let .listing(listingType):
            let sortType = accountService.defaultSortType(forAccountKeychainId: accountKeychainId)
            let feed = accountService.createFeed(
                forAccountKeychainId: accountKeychainId,
                feedType: .frontpage(
                    listingType: listingType,
                    sortType: sortType
                )
            )
            display(feed: feed)

        case let .community(row):
            // Open the full community screen (header + feed), not the bare
            // post list, so subscribe/unsubscribe and the community header are
            // available from the sidebar too.
            //
            // On iPad (regular width) push a two-column reading split — the
            // community feed in the primary column, post detail in the secondary.
            // `SubscriptionsViewController` is the Communities-tab nav root
            // (full-screen, not inside a split primary column), so its
            // `horizontalSizeClass` reliably reflects the window. In compact
            // (iPhone, iPad multitasking) keep the single-column push; nesting a
            // split inside a compact nav stack adds nothing and complicates back
            // navigation.
            if traitCollection.horizontalSizeClass == .regular {
                let split = CommunityReadingSplitViewController(
                    communityName: row.name,
                    instance: row.instanceActorId,
                    accountKeychainId: accountKeychainId,
                    dependencies: dependencies.nested
                )
                navigationController?.pushViewController(split, animated: true)
            } else {
                let communityVC = CommunityOrLoadingViewController(
                    communityName: row.name,
                    instance: row.instanceActorId,
                    accountKeychainId: accountKeychainId,
                    dependencies: dependencies.nested
                )
                navigationController?.pushViewController(communityVC, animated: true)
            }

        case .saved:
            let sortType = accountService.defaultSortType(forAccountKeychainId: accountKeychainId)
            let feed = accountService.createFeed(
                forAccountKeychainId: accountKeychainId,
                feedType: .saved(sortType: sortType)
            )
            display(feed: feed)
        }
    }

    private func display(feed: FeedHandle) {
        let postListVC = PostListViewController(
            feed: feed,
            accountKeychainId: accountKeychainId,
            dependencies: dependencies.nested
        )
        navigationController?.pushViewController(postListVC, animated: true)
    }
}

extension SubscriptionsViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        viewModel.searchText = searchController.searchBar.text ?? ""
    }
}
