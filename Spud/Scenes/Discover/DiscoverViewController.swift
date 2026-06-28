//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import OSLog
import SpudDataKit
import SpudUIKit
import SpudUtilKit
import SwiftUI
import UIKit

private let logger = Logger.app

/// The Discover (Community Explorer) scene. A UIKit shell that owns the
/// navigation chrome (search + sort) and hosts ``DiscoverView`` (SwiftUI). Lives
/// under the Communities tab, reached from its "Explore communities" entry.
/// Tapping a community opens its page, where Subscribe lives.
class DiscoverViewController: UIViewController {
    typealias OwnDependencies =
        HasAccountService &
        HasAlertService &
        HasAppDatabase &
        HasExplorerService &
        HasImageService &
        HasPreferencesService
    typealias NestedDependencies =
        CommunityOrLoadingViewController.Dependencies &
        InstanceDetailViewController.Dependencies
    typealias Dependencies = NestedDependencies & OwnDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    private var imageService: ImageServiceType {
        dependencies.own.imageService
    }

    private var explorerService: ExplorerServiceType {
        dependencies.own.explorerService
    }

    private var preferencesService: PreferencesServiceType {
        dependencies.own.preferencesService
    }

    // MARK: Private

    private let accountKeychainId: String
    private var viewModel: DiscoverViewModel!
    /// Ensures the on-demand community-directory refresh is requested at most once
    /// per visit (a fresh controller is pushed each time Discover is opened).
    private var hasRequestedCommunityRefresh = false

    // MARK: Functions

    init(
        accountKeychainId: String,
        isSignedIn: Bool,
        dependencies: Dependencies
    ) {
        self.dependencies = (own: dependencies, nested: dependencies)
        self.accountKeychainId = accountKeychainId

        super.init(nibName: nil, bundle: nil)

        viewModel = DiscoverViewModel(
            accountScope: dependencies.accountService.scope(forAccountKeychainId: accountKeychainId),
            isSignedIn: isSignedIn,
            dependencies: dependencies,
            onOpenCommunity: { [weak self] row in
                self?.openCommunity(row)
            },
            onOpenPack: { [weak self] pack in
                self?.openPack(pack)
            },
            onOpenInstance: { [weak self] summary in
                self?.openInstance(summary)
            },
            onSeeAllCommunities: { [weak self] title, rows in
                self?.openRailDetail(title: title, rows: rows)
            },
            onSeeAllInstances: { [weak self] title, instances in
                self?.openInstanceRailDetail(title: title, instances: instances)
            },
            onRequestSignIn: { [weak self] in
                self?.presentSignInGate(
                    title: NSLocalizedString(
                        "Sign in to subscribe",
                        comment: "Sign-in gate title when a signed-out user taps Subscribe in Discover"
                    )
                )
            }
        )

        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        requestCommunityRefreshIfEnabled()
    }

    /// Refresh the community directory from the network when Discover is first
    /// shown, if automatic Community Data updates are on. The directory is large,
    /// so it is refreshed on-demand here rather than at launch (which only seeds it
    /// from the bundle). ``ExplorerServiceType/refreshCommunitiesIfStale(maxAge:)``
    /// no-ops while the cache is within the user's chosen refresh interval, and the
    /// view model's live GRDB observation folds any newly-fetched data into the open
    /// screen in place.
    private func requestCommunityRefreshIfEnabled() {
        guard !hasRequestedCommunityRefresh else { return }
        hasRequestedCommunityRefresh = true
        guard preferencesService.explorerAutoRefreshEnabled else { return }
        let maxAge = preferencesService.explorerRefreshInterval.timeInterval
        Task { [explorerService] in
            await explorerService.refreshCommunitiesIfStale(maxAge: maxAge)
        }
    }

    private func setup() {
        view.backgroundColor = Theme.background
        navigationItem.title = NSLocalizedString("Discover", comment: "Discover screen title")

        let accent = Color(ThemeManager.currentAccentColor)
        let rootView = DiscoverView(viewModel: viewModel, accent: accent)
            .environment(\.imageService, imageService)
        let contentVC = UIHostingController(rootView: rootView)
        add(child: contentVC)
        addSubviewWithEdgeConstraints(child: contentVC)

        setupNavigationChrome()
    }

    private func setupNavigationChrome() {
        let search = UISearchController(searchResultsController: nil)
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = NSLocalizedString(
            "Search all communities",
            comment: "Discover search placeholder"
        )
        navigationItem.searchController = search
        navigationItem.hidesSearchBarWhenScrolling = false

        rebuildSortMenu()
    }

    private func rebuildSortMenu() {
        let actions = ExplorerCommunitySort.allCases.map { sort in
            UIAction(
                title: sort.title,
                state: viewModel.sort == sort ? .on : .off
            ) { [weak self] _ in
                self?.setSort(sort)
            }
        }
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "arrow.up.arrow.down.circle"),
            menu: UIMenu(options: .singleSelection, children: actions)
        )
    }

    private func setSort(_ sort: ExplorerCommunitySort) {
        viewModel.sort = sort
        rebuildSortMenu()
    }

    private func openPack(_ pack: ResolvedStarterPack) {
        let accent = Color(ThemeManager.currentAccentColor)
        let detail = PackDetailView(
            viewModel: viewModel,
            pack: pack,
            accent: accent
        )
        .environment(\.imageService, imageService)
        let hosting = UIHostingController(rootView: detail)
        hosting.navigationItem.title = pack.title
        hosting.navigationItem.largeTitleDisplayMode = .never
        navigationController?.pushViewController(hosting, animated: true)
    }

    private func openInstance(_ summary: InstanceSummary) {
        let accent = Color(ThemeManager.currentAccentColor)
        let view = InstanceCommunitiesView(
            viewModel: viewModel,
            host: summary.host,
            communities: viewModel.communities(onInstance: summary.host),
            instanceInfo: viewModel.instanceInfo(forHost: summary.host),
            accent: accent,
            onOpenDetail: { [weak self] in self?.openInstanceDetail(host: summary.host) }
        )
        .environment(\.imageService, imageService)
        let hosting = UIHostingController(rootView: view)
        // The host is shown prominently in the instance card, so the nav title is
        // the generic "Browse by instance" (matching the Discover design), not the
        // host repeated a third time.
        hosting.navigationItem.title = "Browse by instance"
        hosting.navigationItem.largeTitleDisplayMode = .never
        navigationController?.pushViewController(hosting, animated: true)
    }

    /// Push the richer "before you commit" instance detail screen (health band,
    /// stat grid, federation, sign-up actions) for `host`, reached by tapping the
    /// instance lens card. Known hosts open from the directory immediately;
    /// unknown but Lemmy-API-compatible hosts are resolved via a live probe.
    private func openInstanceDetail(host: String) {
        InstanceRouter.openInstance(
            host: host,
            from: self,
            accountKeychainId: accountKeychainId,
            dependencies: dependencies.nested
        )
    }

    /// Push the full ranked list for a community rail ("See all" → Trending /
    /// Rising / Because you follow). Reuses the directory row via ``RailDetailView``.
    private func openRailDetail(title: String, rows: [CommunityListRow]) {
        let accent = Color(ThemeManager.currentAccentColor)
        let view = RailDetailView(viewModel: viewModel, rows: rows, accent: accent)
            .environment(\.imageService, imageService)
        let hosting = UIHostingController(rootView: view)
        hosting.navigationItem.title = title
        hosting.navigationItem.largeTitleDisplayMode = .never
        navigationController?.pushViewController(hosting, animated: true)
    }

    /// Push the full ranked instance list for the "Browse by instance" rail's
    /// "See all". Tapping a row opens that server's communities.
    private func openInstanceRailDetail(title: String, instances: [InstanceSummary]) {
        let accent = Color(ThemeManager.currentAccentColor)
        let view = InstanceRailDetailView(viewModel: viewModel, instances: instances, accent: accent)
            .environment(\.imageService, imageService)
        let hosting = UIHostingController(rootView: view)
        hosting.navigationItem.title = title
        hosting.navigationItem.largeTitleDisplayMode = .never
        navigationController?.pushViewController(hosting, animated: true)
    }

    private func openCommunity(_ row: CommunityListRow) {
        guard let instance = InstanceActorId(from: "https://\(row.instanceHost)") else {
            logger.error("Discover: could not parse instance from \(row.instanceHost, privacy: .public)")
            return
        }
        let communityVC = CommunityOrLoadingViewController(
            communityName: row.name,
            instance: instance,
            accountKeychainId: accountKeychainId,
            dependencies: dependencies.nested
        )
        navigationController?.pushViewController(communityVC, animated: true)
    }
}

extension DiscoverViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        viewModel.searchText = searchController.searchBar.text ?? ""
    }
}
