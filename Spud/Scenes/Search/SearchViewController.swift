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

    /// `internal` (not `private`): it witnesses `PostReminderDispatching.appDatabase`
    /// (`PostContextMenuHost` conformance below), and a protocol witness must be at
    /// least as visible as the protocol requirement even when the conformance is
    /// declared in the same file (mirrors `PostListViewController`'s identical
    /// non-private `appDatabase`/`alertService`/`appearanceService`, made internal
    /// for the same reason).
    var appDatabase: AppDatabase {
        dependencies.own.appDatabase
    }

    /// The post cell reuses the feed's `PostListPostViewModel`, which needs the
    /// appearance / content-detector / preferences services. They already live in
    /// `NestedDependencies` (the child VCs require them), so read them off `nested`
    /// rather than widening `OwnDependencies`.
    private var appearanceService: AppearanceServiceType {
        dependencies.nested.appearanceService
    }

    private var postContentDetector: PostContentDetectorServiceType {
        dependencies.nested.postContentDetectorService
    }

    private var preferencesService: PreferencesServiceType {
        dependencies.nested.preferencesService
    }

    // MARK: Private

    private let accountKeychainId: String
    private let viewModel: SearchViewModel

    /// Server post ids whose NSFW thumbnail the user has revealed this session, so a
    /// revealed search row stays revealed across a reconfigure. Mirrors the feed /
    /// Activity / Person reveal state.
    private var revealedNsfwPostIds: Set<Int64> = []

    private var phaseObservationTask: Task<Void, Never>?
    private var resultsObservationTask: Task<Void, Never>?
    /// Reconfigures the visible `.community` rows whenever
    /// `viewModel.subscribeStates` changes — e.g. the outbox's durable subscribe
    /// mirror lands and turns an optimistic Pending into a confirmed Subscribed —
    /// so a row live-corrects without re-running the search.
    private var subscribeStatesObservationTask: Task<Void, Never>?

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
            appDatabase: appDatabase,
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
        subscribeStatesObservationTask?.cancel()
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
        subscribeStatesObservationTask?.cancel()

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
        subscribeStatesObservationTask = Task { @MainActor [weak self] in
            for await _ in ObservationStream.values(of: { viewModel.subscribeStates }) {
                if Task.isCancelled { break }
                self?.reconfigureCommunityRows()
            }
        }
    }

    /// Reconfigures every currently-shown `.community` item so a change to
    /// `viewModel.subscribeStates` repaints those rows in place. A no-op (no
    /// crash, no visible change) the first time it fires — before any search has
    /// run there are no `.community` items in the snapshot yet.
    private func reconfigureCommunityRows() {
        var snapshot = dataSource.snapshot()
        let communityItems = snapshot.itemIdentifiers.filter {
            if case .community = $0 { return true }
            return false
        }
        guard !communityItems.isEmpty else { return }
        snapshot.reconfigureItems(communityItems)
        dataSource.apply(snapshot, animatingDifferences: false)
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
                return makePostCell(tableView, indexPath: indexPath, result: result)

            case let .community(result):
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: SearchCommunityCell.reuseIdentifier,
                    for: indexPath
                ) as! SearchCommunityCell
                cell.configure(with: result, imageService: imageService)
                // The real 5-state, persisted-DB-wins-over-network state — see
                // `SearchViewModel.subscribeState(for:)`. Applied separately from
                // `configure` so a `reconfigureItems` triggered by the live
                // `subscribeStates` observation re-resolves and repaints just the
                // button without re-fetching the icon/text.
                cell.applySubscribedState(viewModel.subscribeState(for: result))
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

    /// Configures a `SearchPostCell`'s hosted `PostListPostContentView` from the
    /// result's feed row, mirroring `ActivityViewController.makePostCell`: the shared
    /// feed view model (with the author line on and the vote arrows suppressed), plus
    /// the NSFW-reveal callback and thumbnail-tap callbacks that route to PostDetail
    /// (a search row opens the post as a whole; it doesn't open the media viewer).
    private func makePostCell(
        _ tableView: UITableView,
        indexPath: IndexPath,
        result: SearchPostResult
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: SearchPostCell.reuseIdentifier,
            for: indexPath
        ) as! SearchPostCell

        let row = result.row
        let serverPostRowId = row.serverPostId
        let serverPostId = result.serverPostId
        // Defense-in-depth: the NSFW filter (`filteringNsfw`) already drops NSFW posts
        // when Show-NSFW is off, so one should never reach this cell in that state. But
        // if it ever did, force the blur on (and suppress reveal, below) so an opted-out
        // user is never shown a raw NSFW thumbnail — `blurNsfw` and `showNsfw` are
        // independent prefs (blur can be off while Show-NSFW is off).
        let showNsfw = preferencesService.showNsfw
        let cellViewModel = PostListPostViewModel(
            row: row,
            appearance: appearanceService,
            postContentDetector: postContentDetector,
            blurNsfw: preferencesService.blurNsfw || !showNsfw,
            isRevealed: showNsfw && revealedNsfwPostIds.contains(serverPostRowId),
            showsAuthor: true,
            showVoteButtonsOverride: false
        )
        cell.postContentView.configure(with: cellViewModel, imageService: imageService)

        // A blurred NSFW thumbnail reveals on tap; reconfigure just this row so the
        // reveal sticks (search has no backing observation to re-emit it). Reveal is
        // gated on Show-NSFW: an opted-out user can never un-blur (defense-in-depth,
        // paired with the forced blur above — normally no NSFW post reaches here then).
        cell.postContentView.revealNsfwTapped = { [weak self] in
            guard let self, preferencesService.showNsfw else { return }
            revealedNsfwPostIds.insert(serverPostRowId)
            var snapshot = dataSource.snapshot()
            snapshot.reconfigureItems([.post(result)])
            dataSource.apply(snapshot, animatingDifferences: false)
        }

        // Every non-blur thumbnail tap opens the post, matching a whole-row tap: search
        // routes to PostDetail rather than to the media viewer / external link.
        cell.postContentView.imageTapped = { [weak self] _, _, _ in
            self?.openPost(serverPostId: serverPostId)
        }
        cell.postContentView.videoTapped = { [weak self] _ in
            self?.openPost(serverPostId: serverPostId)
        }
        cell.postContentView.linkTapped = { [weak self] _ in
            self?.openPost(serverPostId: serverPostId)
        }
        return cell
    }

    /// Opens PostDetail for a search post result. Shared by the row tap and the
    /// thumbnail-tap callbacks.
    private func openPost(serverPostId: Lemmy.PostID) {
        guard let window = view.window as? MainWindow else { return }
        window.display(serverPostId: serverPostId, accountKeychainId: accountKeychainId)
    }

    /// Pushes the Community screen for a search `.community` result. Shared by
    /// the row tap and the long-press menu's "Open Community" action.
    private func openCommunity(_ result: SearchCommunityResult) {
        let vc = CommunityOrLoadingViewController(
            communityName: result.name,
            instance: result.instance,
            accountKeychainId: accountKeychainId,
            dependencies: dependencies.nested
        )
        navigationController?.pushViewController(vc, animated: true)
    }

    /// Opens PostDetail for a search `.comment` result's parent post. Shared by
    /// the row tap and the long-press menu's "Open Thread" action. Search has
    /// no in-app "jump to comment" entry point, so this opens the whole post,
    /// same as the plain row tap always has.
    private func openComment(_ result: SearchCommentResult) {
        guard let window = view.window as? MainWindow else { return }
        window.display(serverPostId: result.serverPostId, accountKeychainId: accountKeychainId)
    }

    /// Pushes the Person screen for a search `.user` result. Shared by the row
    /// tap and the long-press menu's "Open profile" action.
    private func openUser(_ result: SearchUserResult) {
        let vc = PersonOrLoadingViewController(
            personId: result.serverPersonId,
            instance: result.instance,
            accountKeychainId: accountKeychainId,
            dependencies: dependencies.nested
        )
        navigationController?.pushViewController(vc, animated: true)
    }

    /// The person's canonical profile URL, for the long-press menu's Share
    /// action. `result.name` prefers the person's display name when they set
    /// one, so it isn't safe to use as the URL path segment; the bare Lemmy
    /// username is recovered instead from `qualifiedName` (`@name@host[:port]`,
    /// built from the bare name at `SearchUserResult` construction time).
    private func userProfileURL(for result: SearchUserResult) -> URL? {
        let handle = result.qualifiedName.drop { $0 == "@" }
        guard let bareName = handle.split(separator: "@", maxSplits: 1).first else { return nil }
        return result.instance.url?.appending(path: "u/\(bareName)")
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
        // Optimistic UI: paint the state the outbox is about to durably write
        // (`LemmyService.setSubscribed` enqueues `.pending`, not a bare
        // "Subscribed" — see `CommunitySubscribedState.outboxBaseline`), so a
        // community that requires moderator approval never flashes a
        // false-positive "Subscribed" before the DB observation reconciles to the
        // server's real answer (subscribeStatesObservationTask -> reconfigureItems).
        cell?.applySubscribedState(subscribe ? .pending : .notSubscribed)

        Task { [weak self, weak cell] in
            guard let self else { return }
            do {
                try await viewModel.accountScope.lemmyService
                    .setSubscribed(serverCommunityId: result.serverCommunityId, subscribed: subscribe)
            } catch {
                alertService.handle(error, for: .setSubscribed)
                // Revert to the resolved state (persisted-DB-wins, network
                // fallback) rather than a hardcoded opposite — the enqueue only
                // throws on a defensive precondition (e.g. no outbox), so this
                // is rare, but the resolved state is always the correct one to
                // fall back to.
                cell?.applySubscribedState(viewModel.subscribeState(for: result))
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

    private func pushPerson(personId: Lemmy.PersonID, instance: InstanceActorId) {
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

// MARK: - PostSaveDispatching

extension SearchViewController: PostSaveDispatching {
    var postActionsAccountScope: AccountScope {
        viewModel.accountScope
    }

    var postActionsAlertService: AlertServiceType {
        alertService
    }

    func currentSavedState(serverPostId: Int64) -> Bool {
        postContextRow(forServerPostId: serverPostId)?.isSaved ?? false
    }
}

// MARK: - PostReminderDispatching

/// Search's context menu is rebuilt fresh on every long-press (like the
/// feed's), so there's no cached menu to refresh when a reminder changes.
extension SearchViewController: PostReminderDispatching {
    func remindMeMenuDidChange() { }

    /// The whole-post fields for the "Remind Me…" menu, built from the search
    /// result row at `serverPostId` - nil if the row isn't loaded (long-press
    /// raced a new query replacing the result set). Mirrors the feed's
    /// `remindMeMenuTarget`.
    func remindMeMenuTarget(serverPostId: Int64) -> RemindMeMenuTarget? {
        guard let row = postContextRow(forServerPostId: serverPostId) else { return nil }
        // Prefer the community's own instance host; fall back to the account's
        // home instance so `instanceHost` is never left empty (mirrors the
        // feed's `remindMeMenuTarget`).
        let instanceHost = row.communityActorId.flatMap { InstanceActorId(from: $0)?.host }
            ?? viewModel.accountScope.instanceActorId?.host
            ?? ""
        return RemindMeMenuTarget(
            postServerId: row.serverPostId,
            apId: row.originalPostUrl,
            title: row.title,
            communityName: row.communityName,
            instanceHost: instanceHost,
            thumbnailUrl: row.thumbnailUrl,
            numberOfComments: row.numberOfComments
        )
    }
}

// MARK: - PostContextMenuHost

/// Adopts the shared `PostContextMenuBuilder` for a search post result's
/// long-press menu, reaching feed parity (plan Task 2). Search has no
/// cross-post grouping or moderation context, so `postCrossPostSiblingsSubmenu`
/// / `postModerationSubmenu` are left at `PostContextMenuHost`'s nil defaults.
/// Every action below mirrors its `PostListViewController` counterpart
/// (`PostListViewController.swift:1608-1837`), adapted to Search's
/// `viewModel.accountScope` / `dependencies` seams.
extension SearchViewController: PostContextMenuHost {
    /// The search result row for `serverPostId`, or nil if it isn't (or is no
    /// longer) among the current results — e.g. a long-press raced a new
    /// query replacing the result set.
    func postContextRow(forServerPostId serverPostId: Int64) -> PostListRow? {
        viewModel.results.posts.first { $0.row.serverPostId == serverPostId }?.row
    }

    func postReply(serverPostId: Int64) {
        guard !viewModel.accountScope.isSignedOut else {
            presentSignInGate(title: NSLocalizedString("Sign in to comment", comment: "Sign-in gate title when a signed-out user tries to comment"))
            return
        }
        Haptics.tap()
        let composer = ComposerViewController.makeSheet(
            target: .postReply(serverPostId: Lemmy.PostID(serverPostId)),
            accountKeychainId: accountKeychainId,
            dependencies: dependencies.own
        )
        present(composer, animated: true)
    }

    func postShare(serverPostId: Int64) {
        // Mirrors `PostListViewController.sharePost`: prefer the row's `ap_id`
        // permalink, falling back to the account's home-instance actor id (a
        // raw actor-id STRING, distinct from `AccountScope.instanceActorId`'s
        // typed `InstanceActorId` -- read via the same `AppDatabase` sync
        // helper the feed's view model uses).
        guard let url = LinkURL.forPost(
            instance: preferencesService.shareLinkInstance,
            originalPostUrl: postContextRow(forServerPostId: serverPostId)?.originalPostUrl,
            serverPostId: serverPostId,
            instanceActorId: appDatabase.accountInstanceActorIdSync(forKeychainId: accountKeychainId)
        ) else {
            Haptics.warning()
            return
        }
        presentShareSheet(for: url)
    }

    /// Presents the "Share as Image" editor for the post. Mirrors
    /// ``postShare(serverPostId:)``'s permalink resolution (same
    /// warning-haptic bail when no URL can be formed, or the row isn't
    /// currently loaded) but hands the result to the share-as-image editor
    /// instead of the system share sheet.
    func postShareAsImage(serverPostId: Int64) {
        guard let row = postContextRow(forServerPostId: serverPostId) else {
            Haptics.warning()
            return
        }
        guard let url = LinkURL.forPost(
            instance: preferencesService.shareLinkInstance,
            originalPostUrl: row.originalPostUrl,
            serverPostId: serverPostId,
            instanceActorId: appDatabase.accountInstanceActorIdSync(forKeychainId: accountKeychainId)
        ) else {
            Haptics.warning()
            return
        }
        Haptics.tap()
        let sheet = ShareAsImageViewController.makeSheet(
            content: ShareCardContent(postRow: row, permalink: url),
            imageService: imageService,
            preferencesService: preferencesService
        )
        present(sheet, animated: true)
    }

    func postCrossPost(serverPostId: Int64) {
        guard !viewModel.accountScope.isSignedOut else {
            presentSignInGate(title: NSLocalizedString("Sign in to post", comment: "Sign-in gate title when a signed-out user tries to cross-post"))
            return
        }
        guard let row = postContextRow(forServerPostId: serverPostId) else {
            Haptics.warning()
            return
        }
        Haptics.tap()
        // `NewPostViewController.Dependencies` needs `HasPreferencesService`,
        // which only `NestedDependencies` carries (Search's own
        // `OwnDependencies` doesn't) -- `.nested`, not `.own`.
        let composer = NewPostViewController.makeCrossPostSheet(
            initialTitle: row.title,
            initialUrl: row.url,
            initialBody: crossPostBody(originalApId: row.originalPostUrl, originalBody: nil),
            accountKeychainId: accountKeychainId,
            dependencies: dependencies.nested
        ) { [weak self] clientToken in
            guard let self, let window = view.window as? MainWindow else { return }
            window.displayPending(clientToken: clientToken, accountKeychainId: accountKeychainId)
        }
        present(composer, animated: true)
    }

    func postVisitCommunity(serverPostId: Int64) {
        guard
            let row = postContextRow(forServerPostId: serverPostId),
            let actorId = row.communityActorId,
            let instance = InstanceActorId(from: actorId)
        else {
            Haptics.warning()
            return
        }
        Haptics.tap()
        pushCommunity(name: row.communityName, instance: instance)
    }

    func postViewAuthor(serverPostId: Int64) {
        guard
            let row = postContextRow(forServerPostId: serverPostId),
            let actorId = row.creatorActorId,
            let instance = InstanceActorId(from: actorId)
        else {
            Haptics.warning()
            return
        }
        Haptics.tap()
        pushPerson(personId: Lemmy.PersonID(row.creatorPersonId), instance: instance)
    }

    func postHide(serverPostId: Int64) {
        guard !viewModel.accountScope.isSignedOut else {
            presentSignInGate(title: NSLocalizedString("Sign in to hide posts", comment: "Sign-in gate title when a signed-out user tries to hide a post"))
            return
        }
        // Read live at action time (no caching in the VC) - see AccountScope's
        // doc comment.
        let capabilities = viewModel.accountScope.capabilities
        guard capabilities.can(.hidePosts) else {
            presentCapabilityGate(
                for: .hidePosts,
                host: viewModel.accountScope.instanceActorId?.hostWithPort,
                software: capabilities.software,
                sourceView: nil
            )
            return
        }
        Task { [weak self] in
            guard let self else { return }
            Haptics.tap()
            do {
                try await viewModel.accountScope.lemmyService
                    .hidePost(serverPostId: Lemmy.PostID(serverPostId), hidden: true)
            } catch {
                alertService.handle(error, for: .hidePost)
            }
        }
    }

    func postBlockAuthor(serverPostId: Int64) {
        guard !viewModel.accountScope.isSignedOut else {
            presentSignInGate(title: NSLocalizedString("Sign in to block", comment: "Sign-in gate title when a signed-out user tries to block"))
            return
        }
        guard let row = postContextRow(forServerPostId: serverPostId) else { return }
        let handle = row.creatorName ?? NSLocalizedString("this user", comment: "Fallback author handle when the name is unknown")
        presentDestructiveConfirmation(
            title: String(format: NSLocalizedString("Block %@?", comment: "Block user confirmation title"), handle),
            message: NSLocalizedString(
                "You won't see posts or comments from this user. You can unblock them later.",
                comment: "Block user confirmation message"
            ),
            confirmTitle: NSLocalizedString("Block", comment: "Block user confirm button"),
            sourceView: view
        ) { [weak self] in
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await viewModel.accountScope.lemmyService
                        .setBlocked(serverPersonId: Lemmy.PersonID(row.creatorPersonId), blocked: true)
                } catch {
                    alertService.handle(error, for: .setBlockedPerson)
                }
            }
        }
    }

    func postReport(serverPostId: Int64) {
        guard !viewModel.accountScope.isSignedOut else {
            presentSignInGate(title: NSLocalizedString("Sign in to report", comment: "Sign-in gate title when a signed-out user tries to report"))
            return
        }
        presentReportReasonAlert(
            title: NSLocalizedString("Report post", comment: "Report post dialog title"),
            message: NSLocalizedString("Tell the moderators why you're reporting this post.", comment: "Report post dialog message")
        ) { [weak self] reason in
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await viewModel.accountScope.lemmyService
                        .reportPost(serverPostId: Lemmy.PostID(serverPostId), reason: reason)
                    Haptics.success()
                    presentReportSubmittedConfirmation()
                } catch {
                    alertService.handle(error, for: .reportPost)
                }
            }
        }
    }

    /// Mutes the post's community for `duration` (client-local, not sign-in
    /// gated). Calls the same `AppDatabase` mute API the feed's
    /// `PostListViewModel.muteCommunity(communityActorId:until:)` does --
    /// synchronous, so no `Task` wrapper is needed.
    func postMuteCommunity(serverPostId: Int64, duration: MuteDuration) {
        guard
            let row = postContextRow(forServerPostId: serverPostId),
            let actorId = row.communityActorId
        else {
            Haptics.warning()
            return
        }
        Haptics.tap()
        appDatabase.muteCommunitySync(
            forKeychainId: accountKeychainId,
            communityActorId: actorId,
            until: duration.until
        )
    }
}

// MARK: - CommunityContextMenuHost

/// Adopts the shared `CommunityContextMenuBuilder` for a search `.community`
/// result's long-press menu (plan Task 3), mirroring Discover's
/// `CommunityContextMenu` item-for-item. Unlike Discover's Explorer-directory
/// rows, a search result carries live per-viewer state (`followState`,
/// `serverCommunityId`) straight from the network response, so subscribe/block
/// call `LemmyService` directly instead of first resolving a bare name.
extension SearchViewController: CommunityContextMenuHost {
    func communityOpen(_ result: SearchCommunityResult) {
        Haptics.tap()
        openCommunity(result)
    }

    /// Reuses the existing subscribe-button gating/dispatch (`setSubscribed(result:subscribe:cell:)`
    /// at `:474`), passing `cell: nil` since the long-press menu has no cell to
    /// optimistically update.
    func communitySetSubscribed(_ result: SearchCommunityResult, subscribed: Bool) {
        setSubscribed(result: result, subscribe: subscribed, cell: nil)
    }

    /// Client-local mute state, keyed by the community's federation actor id
    /// (mirrors `DiscoverViewModel.isMuted(_:)`).
    func communityIsMuted(_ result: SearchCommunityResult) -> Bool {
        appDatabase.isCommunityMutedSync(
            forKeychainId: accountKeychainId,
            communityActorId: result.communityUrl
        )
    }

    func communityMute(_ result: SearchCommunityResult, duration: MuteDuration) {
        Haptics.tap()
        appDatabase.muteCommunitySync(
            forKeychainId: accountKeychainId,
            communityActorId: result.communityUrl,
            until: duration.until
        )
    }

    func communityUnmute(_ result: SearchCommunityResult) {
        Haptics.tap()
        appDatabase.unmuteCommunitySync(
            forKeychainId: accountKeychainId,
            communityActorId: result.communityUrl
        )
    }

    func communityShare(_ result: SearchCommunityResult) {
        guard let url = URL(string: result.communityUrl) else {
            Haptics.warning()
            return
        }
        presentShareSheet(for: url)
    }

    func communityCopyLink(_ result: SearchCommunityResult) {
        guard let url = URL(string: result.communityUrl) else {
            Haptics.warning()
            return
        }
        UIPasteboard.general.url = url
        Haptics.tap()
    }

    /// Blocks the community on the signed-in account, gated on sign-in and a
    /// destructive confirmation (mirrors `postBlockAuthor`'s pattern for the
    /// person-block overload).
    func communityBlock(_ result: SearchCommunityResult) {
        guard !viewModel.accountScope.isSignedOut else {
            presentSignInGate(title: NSLocalizedString("Sign in to block", comment: "Sign-in gate title when a signed-out user tries to block"))
            return
        }
        presentDestructiveConfirmation(
            title: String(format: NSLocalizedString("Block %@?", comment: "Block community confirmation title"), "c/\(result.name)"),
            message: NSLocalizedString(
                "You won't see posts or comments from this community. You can unblock it later.",
                comment: "Block community confirmation message"
            ),
            confirmTitle: NSLocalizedString("Block", comment: "Block community confirm button"),
            sourceView: view
        ) { [weak self] in
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await viewModel.accountScope.lemmyService
                        .setBlocked(serverCommunityId: result.serverCommunityId, blocked: true)
                } catch {
                    alertService.handle(error, for: .setBlockedCommunity)
                }
            }
        }
    }
}

// MARK: - CommentContextMenuHost

/// Adopts the shared `CommentContextMenuBuilder` for a search `.comment`
/// result's long-press menu (plan Task 4). Vote/save/report dispatch through
/// the SAME `viewModel.accountScope.lemmyService` comment calls
/// `PostDetailViewController`'s comment context menu uses
/// (`voteOnComment`/`setSavedOnComment`/`PostDetailViewController+Report.swift`'s
/// `reportComment`, `PostDetailViewController.swift:2177-2298`) — unlike posts,
/// there is no shared comment-vote/save dispatch protocol (posts have
/// `PostVoteDispatching`/`PostSaveDispatching`), so this calls the service
/// directly, mirroring PostDetail's own dispatch shape one level down (without
/// its `PostDetailViewModel`/`PostDetailLemmyServicing` indirection, which
/// exists for reasons — pending-comment bookkeeping, offline toasts — that
/// don't apply to a search result row).
extension SearchViewController: CommentContextMenuHost {
    func commentOpenThread(_ result: SearchCommentResult) {
        Haptics.tap()
        openComment(result)
    }

    func commentVote(_ result: SearchCommentResult, direction: VoteStatus.Action) async {
        guard !viewModel.accountScope.isSignedOut else {
            presentSignInGate(title: NSLocalizedString("Sign in to vote", comment: "Sign-in gate title when a signed-out user tries to vote"))
            return
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        do {
            try await viewModel.accountScope.lemmyService
                .vote(serverCommentId: result.serverCommentId, vote: direction)
        } catch {
            alertService.handle(error, for: .vote)
        }
    }

    func commentToggleSave(_ result: SearchCommentResult) {
        guard !viewModel.accountScope.isSignedOut else {
            presentSignInGate(title: NSLocalizedString("Sign in to save", comment: "Sign-in gate title when a signed-out user tries to save a comment"))
            return
        }
        let saved = !result.isSaved
        Task { [weak self] in
            guard let self else { return }
            Haptics.tap()
            do {
                try await viewModel.accountScope.lemmyService
                    .setSaved(serverCommentId: result.serverCommentId, saved: saved)
            } catch {
                alertService.handle(error, for: .save)
            }
        }
    }

    func commentShare(_ result: SearchCommentResult) {
        guard let url = commentShareURL(for: result) else {
            Haptics.warning()
            return
        }
        presentShareSheet(for: url)
    }

    func commentCopyLink(_ result: SearchCommentResult) {
        guard let url = commentShareURL(for: result) else {
            Haptics.warning()
            return
        }
        UIPasteboard.general.url = url
        Haptics.tap()
    }

    func commentViewAuthor(_ result: SearchCommentResult) {
        guard
            let actorId = result.creatorActorId,
            let instance = InstanceActorId(from: actorId)
        else {
            Haptics.warning()
            return
        }
        Haptics.tap()
        pushPerson(personId: result.creatorPersonId, instance: instance)
    }

    func commentReport(_ result: SearchCommentResult) {
        guard !viewModel.accountScope.isSignedOut else {
            presentSignInGate(title: NSLocalizedString("Sign in to report", comment: "Sign-in gate title when a signed-out user tries to report"))
            return
        }
        presentReportReasonAlert(
            title: NSLocalizedString("Report comment", comment: "Report comment dialog title"),
            message: NSLocalizedString("Tell the moderators why you're reporting this comment.", comment: "Report comment dialog message")
        ) { [weak self] reason in
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await viewModel.accountScope.lemmyService
                        .reportComment(serverCommentId: result.serverCommentId, reason: reason)
                    Haptics.success()
                    presentReportSubmittedConfirmation()
                } catch {
                    alertService.handle(error, for: .reportComment)
                }
            }
        }
    }

    /// The comment's canonical share/copy URL, mirroring
    /// `PostDetailViewController.shareComment`: prefers the comment's own
    /// `ap_id` permalink (`result.originalCommentUrl`), falling back to the
    /// account's home-instance actor id.
    private func commentShareURL(for result: SearchCommentResult) -> URL? {
        LinkURL.forComment(
            instance: preferencesService.shareLinkInstance,
            originalCommentUrl: result.originalCommentUrl,
            serverCommentId: Int64(result.serverCommentId),
            instanceActorId: appDatabase.accountInstanceActorIdSync(forKeychainId: accountKeychainId)
        )
    }
}

// MARK: - UserContextMenuHost

/// Adopts the shared `UserContextMenuBuilder` for a search `.user` result's
/// long-press menu (plan Task 5), mirroring `PersonViewController`'s header
/// context menu (Copy handle, Block/Unblock) plus Open profile and Share.
extension SearchViewController: UserContextMenuHost {
    func userOpen(_ result: SearchUserResult) {
        Haptics.tap()
        openUser(result)
    }

    func userCopyHandle(_ result: SearchUserResult) {
        UIPasteboard.general.string = result.qualifiedName
        Haptics.tap()
    }

    func userShare(_ result: SearchUserResult) {
        guard let url = userProfileURL(for: result) else {
            Haptics.warning()
            return
        }
        presentShareSheet(for: url)
    }

    /// Blocks or unblocks the person, gated on sign-in. Blocking presents a
    /// destructive confirmation first (mirrors `postBlockAuthor` /
    /// `PersonViewController.toggleBlockUser`'s blocking branch); unblocking is
    /// not destructive and applies directly, matching `toggleBlockUser`'s
    /// non-blocking branch.
    func userSetBlocked(_ result: SearchUserResult, blocked: Bool) {
        guard !viewModel.accountScope.isSignedOut else {
            presentSignInGate(title: NSLocalizedString("Sign in to block", comment: "Sign-in gate title when a signed-out user tries to block"))
            return
        }
        guard blocked else {
            Task { [weak self] in
                guard let self else { return }
                Haptics.tap()
                do {
                    try await viewModel.accountScope.lemmyService
                        .setBlocked(serverPersonId: result.serverPersonId, blocked: false)
                } catch {
                    alertService.handle(error, for: .setBlockedPerson)
                }
            }
            return
        }
        presentDestructiveConfirmation(
            title: String(format: NSLocalizedString("Block %@?", comment: "Block user confirmation title"), result.qualifiedName),
            message: NSLocalizedString(
                "You won't see posts or comments from this user. You can unblock them later.",
                comment: "Block user confirmation message"
            ),
            confirmTitle: NSLocalizedString("Block", comment: "Block user confirm button"),
            sourceView: view
        ) { [weak self] in
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await viewModel.accountScope.lemmyService
                        .setBlocked(serverPersonId: result.serverPersonId, blocked: true)
                } catch {
                    alertService.handle(error, for: .setBlockedPerson)
                }
            }
        }
    }
}

// MARK: - InstanceContextMenuHost

/// Adopts the shared `InstanceContextMenuBuilder` for a search `.instance`
/// result's long-press menu (plan Task 6). An instance result carries no
/// per-viewer server state (it's a client-side Explorer directory row), so
/// this is the smallest of the five menus: Open, Copy Link, Share, and Add
/// Account Here.
extension SearchViewController: InstanceContextMenuHost {
    func instanceOpen(_ result: SearchInstanceResult) {
        Haptics.tap()
        openInstance(record: result.record)
    }

    func instanceCopyLink(_ result: SearchInstanceResult) {
        UIPasteboard.general.url = URL(string: "https://\(result.baseurl)")
        Haptics.tap()
    }

    func instanceShare(_ result: SearchInstanceResult) {
        guard let url = URL(string: "https://\(result.baseurl)") else {
            Haptics.warning()
            return
        }
        presentShareSheet(for: url)
    }

    /// Presents the login flow for `result`'s instance, wrapped in its own
    /// navigation controller and modally presented -- mirrors
    /// `AccountReauthLauncher.present` (and `MainWindow`'s DEBUG login seam)
    /// rather than pushing it onto Search's own nav stack (which would leave the
    /// flow stranded behind Search on cancel). The login row is built with
    /// `SiteListRow(explorerInstance:)` -- the same Explorer-record transform
    /// `InstanceDetailViewController`'s own sign-in action uses -- so it carries
    /// the directory icon/name, and the user lands on a login screen branded
    /// with the instance they just long-pressed rather than a generic
    /// placeholder (which `SiteListRow.forTypedInstance` would leave nil).
    func instanceAddAccount(_ result: SearchInstanceResult) {
        guard let row = SiteListRow(explorerInstance: result.record) else {
            Haptics.warning()
            return
        }
        Haptics.tap()
        let loginViewController = LoginViewController(row: row, dependencies: dependencies.nested)
        let navigationController = UINavigationController(rootViewController: loginViewController)
        present(navigationController, animated: true)
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
            openPost(serverPostId: result.serverPostId)

        case let .community(result):
            openCommunity(result)

        case let .user(result):
            openUser(result)

        case let .comment(result):
            openComment(result)

        case let .instance(result):
            // Reuse the open-URL instance row's path: push the in-app instance
            // screen for the Explorer record carried by the result.
            openInstance(record: result.record)
        }
    }

    /// Attaches each result kind's long-press menu: post/community/comment/user
    /// reach feed/Discover/PostDetail/Person-header parity (plan Tasks 2-5),
    /// and instance gets its own small Open/Copy Link/Share/Add Account menu
    /// (plan Task 6). Only `.openURL` (the paste-a-link suggestion row) has no
    /// menu.
    func tableView(
        _ tableView: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return nil }
        switch item {
        case let .post(result):
            let general = appearanceService.general
            return UIContextMenuConfiguration(identifier: indexPath as NSCopying, previewProvider: nil) { [weak self] _ in
                guard let self else { return nil }
                return PostContextMenuBuilder.menu(
                    forServerPostId: result.row.serverPostId,
                    host: self,
                    upvoteIcon: general.upvoteIcon,
                    downvoteIcon: general.downvoteIcon
                )
            }
        case let .community(result):
            return UIContextMenuConfiguration(identifier: indexPath as NSCopying, previewProvider: nil) { [weak self] _ in
                guard let self else { return nil }
                return CommunityContextMenuBuilder.menu(
                    for: result,
                    subscribedState: viewModel.subscribeState(for: result),
                    host: self
                )
            }
        case let .comment(result):
            let general = appearanceService.general
            return UIContextMenuConfiguration(identifier: indexPath as NSCopying, previewProvider: nil) { [weak self] _ in
                guard let self else { return nil }
                return CommentContextMenuBuilder.menu(
                    for: result,
                    host: self,
                    upvoteIcon: general.upvoteIcon,
                    downvoteIcon: general.downvoteIcon
                )
            }
        case let .user(result):
            return UIContextMenuConfiguration(identifier: indexPath as NSCopying, previewProvider: nil) { [weak self] _ in
                guard let self else { return nil }
                // Whether this person is blocked can only be learned via a network
                // round trip (`LemmyService.fetchBlockedList`), not a cheap sync
                // lookup, and a menu-build closure must not perform one -- so
                // Search always passes `false`, meaning the menu only ever offers
                // "Block user", never "Unblock" (see `UserContextMenuBuilder`'s
                // doc comment). The person's own profile screen resolves and
                // shows the real state once opened.
                return UserContextMenuBuilder.menu(for: result, isBlocked: false, host: self)
            }
        case let .instance(result):
            return UIContextMenuConfiguration(identifier: indexPath as NSCopying, previewProvider: nil) { [weak self] _ in
                guard let self else { return nil }
                return InstanceContextMenuBuilder.menu(for: result, host: self)
            }
        case .openURL:
            return nil
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
