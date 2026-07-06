//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import OSLog
import SpudDataKit
import SpudUIKit
import SpudUtilKit
import UIKit

private let logger = Logger.app

/// The Search tab. A `UISearchController` drives a scoped, debounced search;
/// results render in a table with feed-style post rows, community/user rows
/// (icon + name + subscribe/avatar), and comment-with-context rows. Tapping a
/// result navigates to PostDetail, the Community screen, or the Person screen.
final class SearchViewController: UIViewController {
    typealias OwnDependencies =
        HasAccountService &
        HasAlertService &
        HasAppDatabase &
        HasImageService
    /// Spelled out as a concrete composition rather than the child VCs'
    /// `Dependencies` typealiases to avoid a recursive typealias cycle
    /// (Search -> Community -> PostList -> PostDetail). This is the union those
    /// expand to; the live `DependencyContainer` conforms to all of them.
    typealias NestedDependencies =
        HasAccountService &
        HasAlertService &
        HasAppDatabase &
        HasAppService &
        HasAppearanceService &
        HasDiagnosticLog &
        HasImageService &
        HasLinkEmbedService &
        HasNodeInfoService &
        HasPostContentDetectorService &
        HasPreferencesService &
        HasReachabilityMonitor &
        HasVoid
    typealias Dependencies = NestedDependencies & OwnDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    private var accountService: AccountServiceType {
        dependencies.own.accountService
    }

    private var alertService: AlertServiceType {
        dependencies.own.alertService
    }

    private var imageService: ImageServiceType {
        dependencies.own.imageService
    }

    private var appDatabase: AppDatabase {
        dependencies.own.appDatabase
    }

    // MARK: Private

    private let accountKeychainId: String
    private let viewModel: SearchViewModel

    private var phaseObservationTask: Task<Void, Never>?
    private var resultsObservationTask: Task<Void, Never>?

    private enum Section: Hashable {
        case openURL
        case results
    }

    private enum Item: Hashable {
        case openURL(kind: SearchURLSuggestion.Kind, displayURL: String)
        case post(SearchPostResult)
        case community(SearchCommunityResult)
        case user(SearchUserResult)
        case comment(SearchCommentResult)
        case instance(SearchInstanceResult)
    }

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 80
        tableView.keyboardDismissMode = .onDrag
        tableView.delegate = self
        tableView.register(SearchPostCell.self, forCellReuseIdentifier: SearchPostCell.reuseIdentifier)
        tableView.register(SearchCommunityCell.self, forCellReuseIdentifier: SearchCommunityCell.reuseIdentifier)
        tableView.register(SearchUserCell.self, forCellReuseIdentifier: SearchUserCell.reuseIdentifier)
        tableView.register(SearchCommentCell.self, forCellReuseIdentifier: SearchCommentCell.reuseIdentifier)
        tableView.register(SearchInstanceCell.self, forCellReuseIdentifier: SearchInstanceCell.reuseIdentifier)
        tableView.register(SearchOpenURLCell.self, forCellReuseIdentifier: SearchOpenURLCell.reuseIdentifier)
        return tableView
    }()

    private lazy var dataSource: UITableViewDiffableDataSource<Section, Item> = makeDataSource()

    private lazy var searchController: UISearchController = {
        let searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = NSLocalizedString(
            "Search",
            comment: "Search bar placeholder"
        )
        searchController.searchBar.delegate = self
        searchController.searchBar.scopeButtonTitles = SearchScope.allCases.map(\.title)
        searchController.searchBar.autocapitalizationType = .none
        return searchController
    }()

    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()

    // MARK: Functions

    init(
        accountKeychainId: String,
        dependencies: Dependencies
    ) {
        self.dependencies = (own: dependencies, nested: dependencies)
        self.accountKeychainId = accountKeychainId

        let appDatabase = dependencies.appDatabase
        viewModel = SearchViewModel(
            accountScope: dependencies.accountService.scope(forAccountKeychainId: accountKeychainId),
            alertService: dependencies.alertService,
            preferencesService: dependencies.preferencesService,
            isKnownInstance: { host in appDatabase.explorerInstanceSync(baseurl: host) != nil },
            searchInstances: { query in
                appDatabase.searchExplorerInstancesSync(query: query)
                    .map(SearchInstanceResult.init)
            }
        )

        super.init(nibName: nil, bundle: nil)

        tabBarItem.title = NSLocalizedString("Search", comment: "Search tab title")
        tabBarItem.image = UIImage(systemName: "magnifyingglass")
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        phaseObservationTask?.cancel()
        resultsObservationTask?.cancel()
    }

    /// Pre-fills and runs a search from an external entry (App Intent / Siri).
    func setSearchQuery(_ query: String) {
        loadViewIfNeeded()
        searchController.isActive = true
        searchController.searchBar.text = query
        viewModel.queryChanged(query)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = Theme.background
        navigationItem.title = NSLocalizedString("Search", comment: "Search screen navigation title")
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false

        view.addSubview(tableView)
        view.addSubview(loadingIndicator)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        startObservations()
        render()
    }

    // MARK: Observation

    private func startObservations() {
        phaseObservationTask?.cancel()
        resultsObservationTask?.cancel()

        let viewModel = viewModel
        phaseObservationTask = Task { @MainActor [weak self] in
            for await _ in ObservationStream.values(of: { viewModel.phase }) {
                if Task.isCancelled { break }
                self?.render()
            }
        }
        resultsObservationTask = Task { @MainActor [weak self] in
            for await _ in ObservationStream.values(of: { (viewModel.urlSuggestion?.displayURL, viewModel.results.posts, viewModel.results.communities, viewModel.results.users, viewModel.results.comments, viewModel.results.instances, viewModel.scope) }) {
                if Task.isCancelled { break }
                self?.render()
            }
        }
    }

    // MARK: Rendering

    private func render() {
        if let suggestion = viewModel.urlSuggestion {
            loadingIndicator.stopAnimating()
            updateContentUnavailable(.none)
            applySnapshot(suggestion: suggestion, items: [])
            return
        }

        switch viewModel.phase {
        case .initial:
            loadingIndicator.stopAnimating()
            applySnapshot(suggestion: nil, items: [])
            updateContentUnavailable(.initial)
        case .loading:
            loadingIndicator.startAnimating()
            updateContentUnavailable(.none)
        case .loaded:
            loadingIndicator.stopAnimating()
            applyResultsSnapshot()
            updateContentUnavailable(
                viewModel.results.isEmpty(for: viewModel.scope) ? .noResults : .none
            )
        case .error:
            loadingIndicator.stopAnimating()
            applySnapshot(suggestion: nil, items: [])
            updateContentUnavailable(.error)
        }
    }

    private func applyResultsSnapshot() {
        let items: [Item]
        switch viewModel.scope {
        case .posts:
            items = viewModel.results.posts.map(Item.post)
        case .communities:
            items = viewModel.results.communities.map(Item.community)
        case .users:
            items = viewModel.results.users.map(Item.user)
        case .comments:
            items = viewModel.results.comments.map(Item.comment)
        case .instances:
            items = viewModel.results.instances.map(Item.instance)
        }
        applySnapshot(suggestion: nil, items: items)
    }

    private func applySnapshot(suggestion: SearchURLSuggestion?, items: [Item]) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        if let suggestion {
            snapshot.appendSections([.openURL])
            snapshot.appendItems(
                [.openURL(kind: suggestion.kind, displayURL: suggestion.displayURL)],
                toSection: .openURL
            )
        }
        snapshot.appendSections([.results])
        snapshot.appendItems(items, toSection: .results)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private enum ContentUnavailable {
        case none
        case initial
        case noResults
        case error
    }

    private func updateContentUnavailable(_ state: ContentUnavailable) {
        switch state {
        case .none:
            contentUnavailableConfiguration = nil
        case .initial:
            var config = UIContentUnavailableConfiguration.empty()
            config.image = UIImage(systemName: "magnifyingglass")
            config.text = NSLocalizedString(
                "Search posts, communities, and people",
                comment: "Search initial empty-state title"
            )
            contentUnavailableConfiguration = config
        case .noResults:
            var config = UIContentUnavailableConfiguration.search()
            config.text = String(
                format: NSLocalizedString(
                    "No results for \"%@\"",
                    comment: "Search no-results title, quotes the query"
                ),
                viewModel.lastSearchedQuery
            )
            contentUnavailableConfiguration = config
        case .error:
            var config = UIContentUnavailableConfiguration.empty()
            config.image = UIImage(systemName: "exclamationmark.triangle")
            config.text = NSLocalizedString(
                "Search failed",
                comment: "Search error-state title"
            )
            config.secondaryText = NSLocalizedString(
                "Check your connection and try again.",
                comment: "Search error-state message"
            )
            contentUnavailableConfiguration = config
        }
    }

    // MARK: Data source

    private func makeDataSource() -> UITableViewDiffableDataSource<Section, Item> {
        UITableViewDiffableDataSource<Section, Item>(tableView: tableView) { [weak self] tableView, indexPath, item in
            guard let self else { return UITableViewCell() }
            switch item {
            case let .openURL(kind, displayURL):
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: SearchOpenURLCell.reuseIdentifier,
                    for: indexPath
                ) as! SearchOpenURLCell
                cell.configure(kind: kind, displayURL: displayURL)
                return cell

            case let .post(result):
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: SearchPostCell.reuseIdentifier,
                    for: indexPath
                ) as! SearchPostCell
                cell.configure(with: result, imageService: imageService)
                return cell

            case let .community(result):
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: SearchCommunityCell.reuseIdentifier,
                    for: indexPath
                ) as! SearchCommunityCell
                cell.configure(with: result, imageService: imageService)
                cell.subscribeTapped = { [weak self, weak cell] subscribe in
                    self?.setSubscribed(result: result, subscribe: subscribe, cell: cell)
                }
                return cell

            case let .user(result):
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: SearchUserCell.reuseIdentifier,
                    for: indexPath
                ) as! SearchUserCell
                cell.configure(with: result, imageService: imageService)
                return cell

            case let .comment(result):
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: SearchCommentCell.reuseIdentifier,
                    for: indexPath
                ) as! SearchCommentCell
                cell.configure(with: result)
                return cell

            case let .instance(result):
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: SearchInstanceCell.reuseIdentifier,
                    for: indexPath
                ) as! SearchInstanceCell
                cell.configure(with: result, imageService: imageService)
                return cell
            }
        }
    }

    // MARK: Actions

    private func setSubscribed(result: SearchCommunityResult, subscribe: Bool, cell: SearchCommunityCell?) {
        guard !viewModel.accountScope.isSignedOut else {
            presentSignInGate(
                title: NSLocalizedString(
                    "Sign in to subscribe",
                    comment: "Sign-in gate title when a signed-out user tries to subscribe from search"
                )
            )
            return
        }

        Haptics.tap()
        // Optimistic UI: reflect the new state immediately.
        cell?.applySubscribedState(subscribe)

        Task { [weak self, weak cell] in
            guard let self else { return }
            do {
                try await viewModel.accountScope.lemmyService
                    .setSubscribed(serverCommunityId: result.serverCommunityId, subscribed: subscribe)
            } catch {
                alertService.handle(error, for: .setSubscribed)
                cell?.applySubscribedState(!subscribe)
            }
        }
    }

    // MARK: Open-URL routing

    /// Routes a detected Lemmy URL. Mirrors PostDetailViewController's local link
    /// handling: communities/instances push directly; canonical URLs resolve
    /// federally first.
    private func openSuggestion(_ link: URL.SpudInternalLink, in window: MainWindow) {
        switch link {
        case let .community(name, instance):
            pushCommunity(name: name, instance: instance)
        case let .instance(instance):
            openInstance(instance)
        case let .objectAtURL(url):
            Task { @MainActor [weak self] in await self?.resolveAndOpen(url, in: window) }
        case let .post(postId, _):
            window.display(serverPostId: postId, accountKeychainId: accountKeychainId)
        case let .person(personId, instance):
            pushPerson(personId: personId, instance: instance)
        }
    }

    private func pushCommunity(name: String, instance: InstanceActorId) {
        let vc = CommunityOrLoadingViewController(
            communityName: name,
            instance: instance,
            accountKeychainId: accountKeychainId,
            dependencies: dependencies.nested
        )
        navigationController?.pushViewController(vc, animated: true)
    }

    private func pushPerson(personId: Components.Schemas.PersonID, instance: InstanceActorId) {
        let vc = PersonOrLoadingViewController(
            personId: personId,
            instance: instance,
            accountKeychainId: accountKeychainId,
            dependencies: dependencies.nested
        )
        navigationController?.pushViewController(vc, animated: true)
    }

    private func openInstance(_ instance: InstanceActorId) {
        InstanceRouter.openInstance(
            host: instance.host,
            from: self,
            accountKeychainId: accountKeychainId,
            dependencies: dependencies.nested
        )
    }

    /// Pushes the in-app instance screen for an Explorer directory record. Shared
    /// by the "Open in Spud" instance row and the Instances-scope result tap.
    private func openInstance(record: ExplorerInstanceRecord) {
        let vc = InstanceExploreViewController(
            record: record,
            accountKeychainId: accountKeychainId,
            dependencies: dependencies.nested
        )
        navigationController?.pushViewController(vc, animated: true)
    }

    /// Resolves a canonical Lemmy URL under the current account, then routes by
    /// type. Comments open the parent post; unresolved links warn.
    private func resolveAndOpen(_ canonicalURL: URL, in window: MainWindow) async {
        let lemmyService = viewModel.accountScope.lemmyService
        let resolved: ResolvedLemmyObject?
        do {
            resolved = try await lemmyService.resolveObject(query: canonicalURL.absoluteString)
        } catch {
            logger.error("resolve_object failed for \(canonicalURL.absoluteString, privacy: .public): \(String(describing: error), privacy: .public)")
            Haptics.warning()
            return
        }
        switch resolved {
        case let .post(postId, _):
            window.display(serverPostId: postId, accountKeychainId: accountKeychainId)
        case let .community(name, instance):
            pushCommunity(name: name, instance: instance)
        case let .person(personId, instance):
            pushPerson(personId: personId, instance: instance)
        case let .comment(postId, _, _):
            window.display(serverPostId: postId, accountKeychainId: accountKeychainId)
        case .unresolved, .none:
            logger.error("Could not resolve an object to display for: \(canonicalURL.absoluteString, privacy: .public)")
            Haptics.warning()
        }
    }
}

// MARK: - UITableViewDelegate

extension SearchViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }

        switch item {
        case .openURL:
            guard let suggestion = viewModel.urlSuggestion,
                  let window = view.window as? MainWindow else { return }
            openSuggestion(suggestion.link, in: window)

        case let .post(result):
            guard let window = view.window as? MainWindow else { return }
            window.display(serverPostId: result.serverPostId, accountKeychainId: accountKeychainId)

        case let .community(result):
            let vc = CommunityOrLoadingViewController(
                communityName: result.name,
                instance: result.instance,
                accountKeychainId: accountKeychainId,
                dependencies: dependencies.nested
            )
            navigationController?.pushViewController(vc, animated: true)

        case let .user(result):
            let vc = PersonOrLoadingViewController(
                personId: result.serverPersonId,
                instance: result.instance,
                accountKeychainId: accountKeychainId,
                dependencies: dependencies.nested
            )
            navigationController?.pushViewController(vc, animated: true)

        case let .comment(result):
            guard let window = view.window as? MainWindow else { return }
            window.display(serverPostId: result.serverPostId, accountKeychainId: accountKeychainId)

        case let .instance(result):
            // Reuse the open-URL instance row's path: push the in-app instance
            // screen for the Explorer record carried by the result.
            openInstance(record: result.record)
        }
    }
}

// MARK: - UISearchResultsUpdating

extension SearchViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        viewModel.queryChanged(searchController.searchBar.text ?? "")
    }
}

// MARK: - UISearchBarDelegate

extension SearchViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, selectedScopeButtonIndexDidChange selectedScope: Int) {
        guard let scope = SearchScope(rawValue: selectedScope) else { return }
        viewModel.scopeChanged(scope)
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        Haptics.tap()
        viewModel.submit()
    }
}
