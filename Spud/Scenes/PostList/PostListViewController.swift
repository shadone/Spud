//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Intents
import LemmyKit
import Observation
import OSLog
import SpudDataKit
import SpudUIKit
import SpudUtilKit
import UIKit

private let logger = Logger.app

class PostListViewController: UIViewController {
    typealias OwnDependencies =
        HasAccountService &
        HasAlertService &
        HasAppDatabase &
        HasAppearanceService &
        HasImageService &
        HasPostContentDetectorService &
        HasPreferencesService
    typealias NestedDependencies =
        PostDetailViewController.Dependencies
    typealias Dependencies = NestedDependencies & OwnDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    var accountService: AccountServiceType {
        dependencies.own.accountService
    }

    var alertService: AlertServiceType {
        dependencies.own.alertService
    }

    var appearanceService: AppearanceServiceType {
        dependencies.own.appearanceService
    }

    var appDatabase: AppDatabase {
        dependencies.own.appDatabase
    }

    var imageService: ImageServiceType {
        dependencies.own.imageService
    }

    var preferencesService: PreferencesServiceType {
        dependencies.own.preferencesService
    }

    // MARK: Public

    private let viewModel: PostListViewModel

    // MARK: UI Properties

    lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.rowHeight = UITableView.automaticDimension

        tableView.delegate = self
        tableView.prefetchDataSource = self

        tableView.register(PostListPostCell.self, forCellReuseIdentifier: PostListPostCell.reuseIdentifier)
        tableView.register(LoadingFooterCell.self, forCellReuseIdentifier: LoadingFooterCell.reuseIdentifier)

        return tableView
    }()

    /// An optional view hosted as the table's `tableHeaderView` so it sits above
    /// the first post and scrolls off-screen with the rows rather than floating
    /// on top. Installed by an embedding host (e.g. `CommunityViewController`)
    /// via `setScrollingHeaderView(_:)`. Held strongly to keep it alive while
    /// installed; it never references back into this controller.
    private var scrollingHeaderView: UIView?

    enum Section: Int, Hashable {
        case posts
        case loading
    }

    enum Item: Hashable {
        /// Server-assigned post id (PostRecord.postId), unique within an account.
        case post(serverPostId: Int64)
        case loadingIndicator
    }

    private var dataSource: UITableViewDiffableDataSource<Section, Item>!

    // MARK: Private

    private var rowsByServerPostId: [Int64: PostListRow] = [:]
    /// In-flight thumbnail prefetch tasks keyed by server post id, so a row that
    /// scrolls back out of the prefetch window can have its warm-up cancelled.
    private var prefetchTasks: [Int64: Task<Void, Never>] = [:]
    /// The full ordered feed snapshot from GRDB (before hide-read filtering).
    private var orderedRows: [PostListRow] = []
    /// The rows actually rendered, after the hide-read filter. Drives the empty
    /// state so an all-read feed shows the designed empty state when hiding.
    private var displayedRows: [PostListRow] = []
    /// The backing account's moderation capability, refreshed when the feed
    /// loads. Drives whether the post context menu shows mod actions. `.none`
    /// until the first fetch (and for signed-out accounts).
    private var moderationCapability: ModerationCapability = .none
    /// Set once the GRDB observation has produced its first snapshot for the
    /// current feed, so the designed empty state only shows after the initial
    /// load settles (not as a flash during first fetch).
    private var hasReceivedFirstSnapshot = false
    private var observationTask: Task<Void, Never>?
    private var titleObservationTask: Task<Void, Never>?
    private var loadingObservationTask: Task<Void, Never>?
    private var fetchFailedObservationTask: Task<Void, Never>?
    private var swipeActionsObservationTask: Task<Void, Never>?
    private var displayPrefsObservationTasks: [Task<Void, Never>] = []

    /// The active post swipe-action config, sanitized for posts. Seeded from
    /// the preference and kept live via `swipeActionsObservationTask`; changes
    /// reconfigure visible cells.
    private var swipeActionConfig: SwipeActionConfig = .defaultPosts

    // MARK: Reading / hiding state (M8)

    /// Hide-read prefs, seeded from `PreferencesService` and kept live. Changes
    /// re-apply the current snapshot through `HideReadPostsFilter`.
    private var hideReadPosts = false
    private var hideReadPostsMode: HideReadPostsFilter.Mode = .onRefresh

    /// Mark-read prefs, seeded and kept live. Drive `scrollViewDidScroll`'s
    /// best-effort mark-as-read.
    private var markPostsRead = true
    private var markPostsReadOnScroll = false

    /// For `HideReadPostsFilter.Mode.onRefresh`: the server post ids that were
    /// already read when the current feed view began, captured on the first
    /// snapshot. Only these are hidden, so posts read mid-session don't vanish
    /// from under the user until the next refresh.
    private var pinnedReadIds: Set<Int64> = []

    /// Server post ids already enqueued for a scroll mark-as-read, so we don't
    /// fire the API repeatedly for the same row.
    private var scrollMarkedReadIds: Set<Int64> = []

    var sortTypeBarButtonItem: UIBarButtonItem!
    var sortTypeMenuActionsBySortType: [Components.Schemas.SortType: UIAction] = [:]

    /// Whether this feed is the Posts-tab root, and so shows the tappable
    /// quick-switch title (chevron) that opens the read-only feed drawer.
    private let showsQuickSwitch: Bool

    /// Retained because UIKit holds the transitioning delegate weakly.
    private let drawerTransitioningDelegate = LeadingDrawerTransitioningDelegate()

    private lazy var quickSwitchTitleButton: UIButton = makeQuickSwitchTitleButton()

    // MARK: Functions

    init(
        feed: FeedHandle,
        accountKeychainId: String,
        showsQuickSwitch: Bool = false,
        dependencies: Dependencies
    ) {
        self.dependencies = (own: dependencies, nested: dependencies)
        self.showsQuickSwitch = showsQuickSwitch

        viewModel = PostListViewModel(
            feed: feed,
            accountKeychainId: accountKeychainId,
            dependencies: dependencies
        )

        super.init(nibName: nil, bundle: nil)

        swipeActionConfig = dependencies.preferencesService
            .postSwipeActions
            .sanitized(for: .post)

        hideReadPosts = dependencies.preferencesService.hideReadPosts
        hideReadPostsMode = dependencies.preferencesService.hideReadPostsMode
        markPostsRead = dependencies.preferencesService.markPostsRead
        markPostsReadOnScroll = dependencies.preferencesService.markPostsReadOnScroll

        setup()
        configureTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        observationTask?.cancel()
        titleObservationTask?.cancel()
        loadingObservationTask?.cancel()
        fetchFailedObservationTask?.cancel()
        swipeActionsObservationTask?.cancel()
        for task in displayPrefsObservationTasks {
            task.cancel()
        }
    }

    private func setup() {
        view.backgroundColor = .white
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        setupDataSource()
        setupSortTypeMenu()
        setupComposeButton()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // The table width is only known after layout; (re)size the scrolling
        // header to it. Guarded against no-op churn, so this is cheap to call
        // every pass and handles rotation / width changes for free.
        layoutScrollingHeaderIfNeeded()
    }

    // MARK: Scrolling header

    /// Installs a view that scrolls together with the feed, pinned above the
    /// first post (the table's `tableHeaderView`) instead of floating above the
    /// table. Used by `CommunityViewController` to host the community header so
    /// its potentially tall content (description, rules) scrolls with the posts
    /// rather than occupying fixed space at the top. Pass nil to remove it.
    func setScrollingHeaderView(_ header: UIView?) {
        // The table positions its header by frame, so opt the view out of Auto
        // Layout for its own frame while its subviews keep using constraints.
        header?.translatesAutoresizingMaskIntoConstraints = true
        scrollingHeaderView = header
        tableView.tableHeaderView = header
        layoutScrollingHeaderIfNeeded()
    }

    /// Re-measures the scrolling header against the current table width and
    /// commits its height. Safe to call repeatedly: it only reassigns the
    /// `tableHeaderView` when the resolved size actually changes. Call after the
    /// header's content changes height (e.g. once community info loads).
    func layoutScrollingHeaderIfNeeded() {
        guard let header = scrollingHeaderView else { return }
        let width = tableView.bounds.width
        guard width > 0 else { return }

        header.frame.size.width = width
        let height = header.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height

        guard abs(header.frame.height - height) > 0.5 else { return }
        header.frame.size.height = height
        // Reassigning is what makes the table adopt the new header height.
        tableView.tableHeaderView = header
    }

    /// Adds a compose entry to the nav bar on the standalone frontpage feed.
    /// Community feeds are embedded children whose host (`CommunityViewController`)
    /// owns the nav bar and provides its own community-prefilled "New post"
    /// button, and saved feeds have no single community to post to.
    private func setupComposeButton() {
        guard case .frontpage = viewModel.feed.feedType else {
            // Saved / community feeds have no single community to post to.
            navigationItem.leftBarButtonItem = nil
            return
        }
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "square.and.pencil"),
            style: .plain,
            target: self,
            action: #selector(composeTapped)
        )
    }

    // MARK: Quick-switch drawer

    private func configureTitle() {
        if showsQuickSwitch {
            navigationItem.titleView = quickSwitchTitleButton
        }
        applyNavigationTitle()
    }

    private func applyNavigationTitle() {
        if showsQuickSwitch {
            updateQuickSwitchTitle(viewModel.navigationTitle)
        } else {
            navigationItem.title = viewModel.navigationTitle
        }
    }

    private func makeQuickSwitchTitleButton() -> UIButton {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(
            systemName: "chevron.down",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        )
        config.imagePlacement = .trailing
        config.imagePadding = 5
        config.baseForegroundColor = .label
        config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 17, weight: .semibold)
            return outgoing
        }
        let button = UIButton(configuration: config)
        button.addTarget(self, action: #selector(quickSwitchTapped), for: .touchUpInside)
        button.accessibilityHint = NSLocalizedString(
            "Opens the feed switcher",
            comment: "Accessibility hint for the tappable feed title"
        )
        return button
    }

    private func updateQuickSwitchTitle(_ text: String) {
        quickSwitchTitleButton.configuration?.title = text
        quickSwitchTitleButton.sizeToFit()
    }

    @objc
    private func quickSwitchTapped() {
        Haptics.tap()
        let keychainId = viewModel.accountKeychainId
        let drawer = QuickSwitchDrawerViewController(
            activeFeedType: viewModel.feed.feedType,
            defaultSortType: accountService.defaultSortType(forAccountKeychainId: keychainId)
        )
        drawer.onSelectFeedType = { [weak self] feedType in
            self?.switchFeed(to: feedType)
        }
        drawer.onBrowseAllCommunities = { [weak self] in
            // Communities is tab index 1 (Posts | Communities | Search | Inbox | Account).
            self?.tabBarController?.selectedIndex = 1
        }

        let navigationController = UINavigationController(rootViewController: drawer)
        navigationController.modalPresentationStyle = .custom
        navigationController.transitioningDelegate = drawerTransitioningDelegate
        present(navigationController, animated: true)
    }

    /// Switches the feed in place (drawer selection), mirroring the sort-change
    /// path: swap the feed, restart the observation, and refresh the chrome.
    private func switchFeed(to feedType: FeedType) {
        viewModel.switchFeed(to: feedType)
        feedChanged()
        setupComposeButton()
        rebuildSortTypeMenu(activeSortType: viewModel.feed.feedType.sortType)
        applyNavigationTitle()
        donateIntent()
    }

    @objc
    private func composeTapped() {
        let keychainId = viewModel.accountKeychainId
        guard !accountService.isSignedOut(forAccountKeychainId: keychainId) else {
            presentSignInGate(
                title: NSLocalizedString("Sign in to post", comment: "Sign-in gate title when a signed-out user tries to create a post")
            )
            return
        }

        Haptics.tap()
        let composer = NewPostViewController.makeSheet(
            serverCommunityId: nil,
            initialCommunityName: nil,
            accountKeychainId: keychainId,
            dependencies: dependencies.own
        ) { [weak self] serverPostId in
            guard let window = self?.view.window as? MainWindow else { return }
            window.display(serverPostId: serverPostId, accountKeychainId: keychainId)
        }
        present(composer, animated: true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        startObservations()
        feedChanged()
        donateIntent()
    }

    private func startObservations() {
        titleObservationTask?.cancel()
        loadingObservationTask?.cancel()
        fetchFailedObservationTask?.cancel()
        swipeActionsObservationTask?.cancel()
        for task in displayPrefsObservationTasks {
            task.cancel()
        }
        displayPrefsObservationTasks.removeAll()

        swipeActionsObservationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await config in preferencesService.postSwipeActionsStream {
                if Task.isCancelled { break }
                let sanitized = config.sanitized(for: .post)
                guard sanitized != swipeActionConfig else { continue }
                swipeActionConfig = sanitized
                reconfigureVisibleSwipeActions()
            }
        }

        startDisplayAndReadingObservations()

        let viewModel = viewModel
        titleObservationTask = Task { @MainActor [weak self] in
            for await _ in Self.values(of: { viewModel.navigationTitle }) {
                if Task.isCancelled { break }
                self?.applyNavigationTitle()
            }
        }
        loadingObservationTask = Task { @MainActor [weak self] in
            for await _ in Self.values(of: { viewModel.isFetchingNextPage }) {
                if Task.isCancelled { break }
                self?.applyLoadingIndicatorVisibility(hidden: !viewModel.isFetchingNextPage)
            }
        }
        fetchFailedObservationTask = Task { @MainActor [weak self] in
            for await failed in Self.values(of: { viewModel.fetchFailed }) {
                if Task.isCancelled { break }
                self?.handleFetchFailedChange(failed)
            }
        }
    }

    /// A page fetch threw. With posts already on screen this was a pagination
    /// failure, so surface a transient alert and keep the feed visible. With an
    /// empty feed it was the initial load, so let the content-unavailable state
    /// take over with the designed "Couldn't reach ..." error and its actions.
    private func handleFetchFailedChange(_ failed: Bool) {
        guard failed else {
            updateContentUnavailableState()
            return
        }
        if displayedRows.isEmpty {
            updateContentUnavailableState()
        } else if let error = viewModel.lastFetchError {
            alertService.handle(error, for: .fetchPostList)
            viewModel.fetchFailed = false
        }
    }

    /// Observes the M8 reading / display preferences. Density, thumbnail
    /// position, and text scale rebuild visible cells; hide-read and mark-read
    /// prefs update the snapshot / scroll behaviour live, with no relaunch.
    private func startDisplayAndReadingObservations() {
        // Display prefs (density, thumbnail position, text scale) all rebuild
        // visible cells. Each stream replays its current value on subscribe, so
        // the first element is skipped (the cells already reflect it).
        displayPrefsObservationTasks.append(Task { @MainActor [weak self] in
            guard let self else { return }
            var first = true
            for await _ in preferencesService.postDensityStream {
                if Task.isCancelled { break }
                if first { first = false
                    continue
                }
                reconfigureVisibleCells()
            }
        })

        displayPrefsObservationTasks.append(Task { @MainActor [weak self] in
            guard let self else { return }
            var first = true
            for await _ in preferencesService.thumbnailPositionStream {
                if Task.isCancelled { break }
                if first { first = false
                    continue
                }
                reconfigureVisibleCells()
            }
        })

        displayPrefsObservationTasks.append(Task { @MainActor [weak self] in
            guard let self else { return }
            var first = true
            for await _ in preferencesService.postTextScaleStream {
                if Task.isCancelled { break }
                if first { first = false
                    continue
                }
                reconfigureVisibleCells()
            }
        })

        displayPrefsObservationTasks.append(Task { @MainActor [weak self] in
            guard let self else { return }
            var first = true
            for await _ in preferencesService.showVoteButtonsStream {
                if Task.isCancelled { break }
                if first { first = false
                    continue
                }
                reconfigureVisibleCells()
            }
        })

        // The upvote tint follows the accent, so a change of accent must
        // recolor the visible vote arrows and scores.
        displayPrefsObservationTasks.append(Task { @MainActor [weak self] in
            guard let self else { return }
            var first = true
            for await _ in preferencesService.accentColorStream {
                if Task.isCancelled { break }
                if first { first = false
                    continue
                }
                reconfigureVisibleCells()
            }
        })

        displayPrefsObservationTasks.append(Task { @MainActor [weak self] in
            guard let self else { return }
            for await value in preferencesService.hideReadPostsStream {
                if Task.isCancelled { break }
                guard value != hideReadPosts else { continue }
                hideReadPosts = value
                // Re-pin the read set so toggling on doesn't instantly sweep
                // posts read earlier this session under onRefresh.
                pinnedReadIds = HideReadPostsFilter.readIds(in: orderedRows)
                apply(rows: orderedRows)
            }
        })

        displayPrefsObservationTasks.append(Task { @MainActor [weak self] in
            guard let self else { return }
            for await value in preferencesService.hideReadPostsModeStream {
                if Task.isCancelled { break }
                guard value != hideReadPostsMode else { continue }
                hideReadPostsMode = value
                apply(rows: orderedRows)
            }
        })

        displayPrefsObservationTasks.append(Task { @MainActor [weak self] in
            guard let self else { return }
            for await value in preferencesService.markPostsReadStream {
                if Task.isCancelled { break }
                markPostsRead = value
            }
        })

        displayPrefsObservationTasks.append(Task { @MainActor [weak self] in
            guard let self else { return }
            for await value in preferencesService.markPostsReadOnScrollStream {
                if Task.isCancelled { break }
                markPostsReadOnScroll = value
            }
        })
    }

    /// Re-applies the diffable snapshot's currently visible items so each cell
    /// rebuilds its view model from the updated display preferences (density,
    /// thumbnail position, text scale).
    private func reconfigureVisibleCells() {
        guard dataSource != nil else { return }
        var snapshot = dataSource.snapshot()
        let items = snapshot.itemIdentifiers
        guard !items.isEmpty else { return }
        snapshot.reconfigureItems(items)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    /// Tiny shim that turns an Observable property into an AsyncStream of
    /// values via the standard `withObservationTracking` loop. Uses
    /// `ObservationScheduler` to break the @Sendable onChange / @MainActor
    /// observe-recursion loop into an instance method capture.
    @MainActor
    private static func values<Value: Sendable>(
        of access: @escaping @MainActor () -> Value
    ) -> AsyncStream<Value> {
        AsyncStream { continuation in
            let scheduler = ObservationScheduler<Value>(
                continuation: continuation,
                access: access
            )
            scheduler.observe()
        }
    }

    private func setupSortTypeMenu() {
        func makeAction(for sortType: Components.Schemas.SortType) -> UIAction {
            let menuItem = sortType.itemForMenu
            let action = UIAction(
                title: menuItem.title,
                image: menuItem.image
            ) { [weak self] _ in
                self?.sortTypeChanged(to: sortType)
            }
            sortTypeMenuActionsBySortType[sortType] = action
            return action
        }

        let actives: [Components.Schemas.SortType] = [
            .Active, .Hot, .New, .Old, .Controversial, .Scaled,
        ]
        let tops: [Components.Schemas.SortType] = [
            .TopSixHour, .TopTwelveHour, .TopDay, .TopWeek, .TopMonth,
            .TopThreeMonths, .TopSixMonths, .TopNineMonths, .TopYear, .TopAll,
        ]
        let comments: [Components.Schemas.SortType] = [
            .MostComments, .NewComments,
        ]

        for sortType in actives + tops + comments {
            _ = makeAction(for: sortType)
        }

        sortTypeBarButtonItem = UIBarButtonItem(
            title: "Sort type",
            image: UIImage(systemName: "line.horizontal.3.decrease.circle"),
            menu: nil
        )
        navigationItem.rightBarButtonItem = sortTypeBarButtonItem

        rebuildSortTypeMenu(activeSortType: viewModel.feed.feedType.sortType)
    }

    private func rebuildSortTypeMenu(activeSortType: Components.Schemas.SortType) {
        for (sortType, action) in sortTypeMenuActionsBySortType {
            action.state = (sortType == activeSortType) ? .on : .off
        }

        let actives: [Components.Schemas.SortType] = [
            .Active, .Hot, .New, .Old, .Controversial, .Scaled,
        ]
        let tops: [Components.Schemas.SortType] = [
            .TopSixHour, .TopTwelveHour, .TopDay, .TopWeek, .TopMonth,
            .TopThreeMonths, .TopSixMonths, .TopNineMonths, .TopYear, .TopAll,
        ]
        let comments: [Components.Schemas.SortType] = [
            .MostComments, .NewComments,
        ]

        let sortTypeMenu = UIMenu(
            title: "",
            options: .singleSelection,
            children: [
                UIMenu(title: "", options: .displayInline, children: actives.compactMap { sortTypeMenuActionsBySortType[$0] }),
                UIMenu(title: "Top", options: .singleSelection, children: tops.compactMap { sortTypeMenuActionsBySortType[$0] }),
                UIMenu(title: "", options: .displayInline, children: comments.compactMap { sortTypeMenuActionsBySortType[$0] }),
            ]
        )

        sortTypeBarButtonItem.menu = sortTypeMenu
    }

    private func sortTypeChanged(to sortType: Components.Schemas.SortType) {
        viewModel.didChangeSortType(sortType)
        feedChanged()
        rebuildSortTypeMenu(activeSortType: viewModel.feed.feedType.sortType)
        donateIntent()
    }

    /// Reloads the feed from scratch (a fresh feed key + re-fetch). Used after
    /// an action that changes server-side filtering, such as blocking a user or
    /// community, so the now-excluded content disappears.
    func reloadFeed() {
        viewModel.didClickReload()
        feedChanged()
    }

    /// Refreshes the backing account's moderation capability from the server.
    /// Best-effort: a failure (or signed-out account) leaves it at `.none`,
    /// hiding mod actions.
    private func refreshModerationCapability() {
        let keychainId = viewModel.accountKeychainId
        Task { @MainActor [weak self] in
            guard let self else { return }
            let capability = await (
                try? accountService
                    .lemmyService(forAccountKeychainId: keychainId)
                    .fetchModerationCapability()
            ) ?? .none
            guard !Task.isCancelled else { return }
            moderationCapability = capability
        }
    }

    private lazy var loadingSkeletonView = FeedLoadingSkeletonView()

    /// Shows the skeleton placeholder as the table background during the initial
    /// fetch; removed once the first snapshot (or a failure) arrives.
    private func showLoadingSkeleton() {
        guard tableView.backgroundView !== loadingSkeletonView else { return }
        tableView.backgroundView = loadingSkeletonView
        loadingSkeletonView.startAnimating()
    }

    private func hideLoadingSkeleton() {
        guard tableView.backgroundView === loadingSkeletonView else { return }
        loadingSkeletonView.stopAnimating()
        tableView.backgroundView = nil
    }

    private func feedChanged() {
        observationTask?.cancel()
        rowsByServerPostId.removeAll()
        orderedRows.removeAll()
        displayedRows.removeAll()
        pinnedReadIds.removeAll()
        scrollMarkedReadIds.removeAll()
        hasReceivedFirstSnapshot = false
        // Clear any error carried over from the feed we're leaving so it can't
        // flash before the new feed's fetch starts.
        viewModel.fetchFailed = false
        updateContentUnavailableState()
        showLoadingSkeleton()
        refreshModerationCapability()

        applyLoadingIndicatorVisibility(hidden: !viewModel.isFetchingNextPage)

        let feedKey = viewModel.feed.feedKey
        observationTask = Task { @MainActor [weak self] in
            guard let self else { return }

            // Feeds are created lazily by the importer on the first fetch.
            // If the row doesn't exist yet, await the first page so the
            // importer creates it before we set up the observation.
            if appDatabase.feedRowIdSync(forFeedKey: feedKey) == nil {
                await viewModel.fetchNextPage()
                if Task.isCancelled { return }
            }

            guard let feedRowId = appDatabase.feedRowIdSync(forFeedKey: feedKey) else {
                hideLoadingSkeleton()
                return
            }

            for await rows in appDatabase.observePostListRows(feedId: feedRowId) {
                if Task.isCancelled { break }
                let isFirstSnapshot = !hasReceivedFirstSnapshot
                hasReceivedFirstSnapshot = true
                if isFirstSnapshot {
                    hideLoadingSkeleton()
                    // Pin the rows already read when this feed view began, so
                    // `onRefresh` hide-read only hides those (posts read while
                    // scrolling stay until the next refresh).
                    pinnedReadIds = HideReadPostsFilter.readIds(in: rows)
                }
                // Live feed emissions never animate structurally. The first
                // snapshot would otherwise scale every cell in from the top-left
                // during the table's initial layout; a paginated insert would
                // animate the appended rows' height from zero as they scroll into
                // view. Cells whose data changed are reconfigured in place either
                // way. The deliberate hide-read toggle still animates its removals.
                apply(rows: rows, animatingDifferences: false)
                if isFirstSnapshot {
                    viewModel.didPrepareObservation(numberOfFetchedPosts: rows.count)
                }
            }
        }
    }

    private func apply(rows: [PostListRow], animatingDifferences: Bool = true) {
        orderedRows = rows

        // Filter for display per the hide-read preference. `rowsByServerPostId`
        // still maps every row so cells resolve, but the snapshot only carries
        // the rows that should be visible.
        let displayed = HideReadPostsFilter.filter(
            rows: rows,
            enabled: hideReadPosts,
            mode: hideReadPostsMode,
            pinnedReadIds: pinnedReadIds
        )
        displayedRows = displayed
        rowsByServerPostId = Dictionary(uniqueKeysWithValues: rows.map { ($0.serverPostId, $0) })

        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.posts])
        let items = displayed.map { Item.post(serverPostId: $0.serverPostId) }
        snapshot.appendItems(items, toSection: .posts)
        // Refresh content in place. The item identity is the serverPostId, so a
        // GRDB emission that only changes a post's data (vote, read-state) or
        // appends a page leaves surviving cells stale unless we tell the data
        // source to re-run the cell provider for them. Reconfigure (not reload)
        // does that on the existing cells, avoiding the cross-dissolve that
        // reloadItems animates under `animatingDifferences: true` — that fade,
        // applied to every visible cell at once, flashed the whole list on each
        // pagination. Matches reconfigureVisibleCells()/reconfigureVisibleSwipeActions().
        snapshot.reconfigureItems(items)

        if viewModel.isFetchingNextPage {
            snapshot.appendSections([.loading])
            snapshot.appendItems([.loadingIndicator], toSection: .loading)
        }

        dataSource.apply(snapshot, animatingDifferences: animatingDifferences)

        updateContentUnavailableState()
    }

    private func applyLoadingIndicatorVisibility(hidden: Bool) {
        guard dataSource != nil else { return }

        var snapshot = dataSource.snapshot()
        let hasLoadingSection = snapshot.sectionIdentifiers.contains(.loading)

        if hidden {
            if hasLoadingSection {
                snapshot.deleteSections([.loading])
                dataSource.apply(snapshot, animatingDifferences: true)
            }
        } else if !hasLoadingSection {
            snapshot.appendSections([.loading])
            snapshot.appendItems([.loadingIndicator], toSection: .loading)
            dataSource.apply(snapshot, animatingDifferences: true)
        }

        updateContentUnavailableState()
    }

    /// Drives the full-screen content-unavailable surface once the feed has
    /// settled (first snapshot in, not mid-fetch) and has no posts to show:
    /// the designed error state when the initial load failed, otherwise the
    /// empty state (e.g. "No saved posts yet"). Hidden while posts exist or a
    /// fetch is in flight.
    private func updateContentUnavailableState() {
        let isSettledAndEmpty = displayedRows.isEmpty && !viewModel.isFetchingNextPage

        if viewModel.fetchFailed, isSettledAndEmpty {
            hideLoadingSkeleton()
            contentUnavailableConfiguration = makeErrorConfiguration()
            return
        }

        guard hasReceivedFirstSnapshot, isSettledAndEmpty else {
            contentUnavailableConfiguration = nil
            return
        }

        let empty = viewModel.emptyState
        var config = UIContentUnavailableConfiguration.empty()
        config.image = UIImage(systemName: empty.symbolName)
        config.text = empty.title
        config.secondaryText = empty.message
        contentUnavailableConfiguration = config
    }

    /// The designed feed error state: a globe glyph, "Couldn't reach <host>",
    /// a reassuring line, and Try again / Work offline actions.
    private func makeErrorConfiguration() -> UIContentUnavailableConfiguration {
        var config = UIContentUnavailableConfiguration.empty()
        config.image = UIImage(systemName: "globe")

        if let host = viewModel.instanceHost {
            config.text = String(
                format: NSLocalizedString(
                    "Couldn't reach %@",
                    comment: "Feed error-state title; %@ is the instance host, e.g. lemmy.world"
                ),
                host
            )
        } else {
            config.text = NSLocalizedString(
                "Couldn't reach the server",
                comment: "Feed error-state title when the instance host is unknown"
            )
        }
        config.secondaryText = NSLocalizedString(
            "Check your connection and try again.",
            comment: "Feed error-state message"
        )

        var tryAgain = UIButton.Configuration.borderedProminent()
        tryAgain.title = NSLocalizedString("Try again", comment: "Feed error-state primary action")
        tryAgain.baseBackgroundColor = ThemeManager.currentAccentColor
        config.button = tryAgain
        config.buttonProperties.primaryAction = UIAction { [weak self] _ in
            guard let self else { return }
            Task { await self.viewModel.fetchNextPage() }
        }

        var workOffline = UIButton.Configuration.plain()
        workOffline.title = NSLocalizedString("Work offline", comment: "Feed error-state secondary action")
        config.secondaryButton = workOffline
        config.secondaryButtonProperties.primaryAction = UIAction { [weak self] _ in
            guard let self else { return }
            viewModel.fetchFailed = false
            updateContentUnavailableState()
        }

        return config
    }

    private func setupDataSource() {
        let appearance = appearanceService
        let imageService = imageService
        let postContentDetector = dependencies.own.postContentDetectorService

        dataSource = UITableViewDiffableDataSource<Section, Item>(
            tableView: tableView
        ) { [weak self] tableView, indexPath, item in
            switch item {
            case let .post(serverPostId):
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: PostListPostCell.reuseIdentifier,
                    for: indexPath
                ) as! PostListPostCell

                guard let row = self?.rowsByServerPostId[serverPostId] else {
                    logger.assertionFailure("Missing PostListRow for serverPostId \(serverPostId)")
                    return cell
                }

                let viewModel = PostListPostViewModel(
                    row: row,
                    appearance: appearance,
                    postContentDetector: postContentDetector
                )
                cell.configure(with: viewModel, imageService: imageService)

                cell.imageTapped = { [weak self] imageUrl, thumbnailUrl, thumbnailImage in
                    self?.presentMediaViewer(
                        imageUrl: imageUrl,
                        thumbnailUrl: thumbnailUrl,
                        preloadedImage: thumbnailImage,
                        altText: row.altText
                    )
                }

                cell.videoTapped = { [weak self] videoUrl in
                    self?.presentVideoPlayer(url: videoUrl)
                }

                let general = appearance.general
                cell.swipeActionConfiguration = self?.swipeActionConfig.viewConfiguration(
                    state: Self.swipeState(for: row),
                    appearance: general
                )

                cell.swipeActionTriggered = { [weak self] trigger in
                    guard let self else { return }
                    let action = swipeActionConfig.action(for: SwipeActionSlot(trigger: trigger))
                    performSwipeAction(action, serverPostId: serverPostId)
                }

                cell.voteTapped = { [weak self] action in
                    guard let self else { return }
                    Task { await self.vote(serverPostId: serverPostId, action: action) }
                }

                return cell

            case .loadingIndicator:
                return tableView.dequeueReusableCell(
                    withIdentifier: LoadingFooterCell.reuseIdentifier,
                    for: indexPath
                )
            }
        }
    }

    /// The current toggle state a row exposes to the swipe presentation layer,
    /// so e.g. the save slot shows "unsave" when already saved.
    private static func swipeState(for row: PostListRow) -> SwipeActionState {
        SwipeActionState(
            isSaved: row.isSaved,
            isUpvoted: row.voteStatus == 1,
            isDownvoted: row.voteStatus == 0
        )
    }

    /// Dispatches a configured swipe action for a post to its existing handler.
    /// `.none` and comment-only actions (already sanitized out for posts) are
    /// no-ops.
    private func performSwipeAction(_ action: SwipeAction, serverPostId: Int64) {
        switch action {
        case .none, .collapse:
            break
        case .upvote:
            Task { await vote(serverPostId: serverPostId, action: .upvote) }
        case .downvote:
            Task { await vote(serverPostId: serverPostId, action: .downvote) }
        case .save:
            toggleSaved(serverPostId: serverPostId)
        case .reply:
            replyToPost(serverPostId: serverPostId)
        case .share:
            sharePost(serverPostId: serverPostId)
        }
    }

    /// Re-applies the diffable snapshot's currently visible items so each cell
    /// rebuilds its swipe configuration from the updated `swipeActionConfig`.
    private func reconfigureVisibleSwipeActions() {
        guard dataSource != nil else { return }
        var snapshot = dataSource.snapshot()
        let items = snapshot.itemIdentifiers
        guard !items.isEmpty else { return }
        snapshot.reconfigureItems(items)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    /// Opens the composer to reply to the post (a top-level comment), gating on
    /// sign-in.
    private func replyToPost(serverPostId: Int64) {
        let keychainId = viewModel.accountKeychainId
        guard !accountService.isSignedOut(forAccountKeychainId: keychainId) else {
            presentSignInGate(
                title: NSLocalizedString("Sign in to comment", comment: "Sign-in gate title when a signed-out user tries to comment")
            )
            return
        }
        Haptics.tap()
        let composer = ComposerViewController.makeSheet(
            target: .postReply(serverPostId: Components.Schemas.PostID(serverPostId)),
            accountKeychainId: keychainId,
            dependencies: dependencies.own
        )
        present(composer, animated: true)
    }

    /// Pushes the post's community screen. Browsing is allowed signed-out, so
    /// this is not gated.
    private func visitCommunity(serverPostId: Int64) {
        guard
            let row = rowsByServerPostId[serverPostId],
            let actorId = row.communityActorId,
            let instance = InstanceActorId(from: actorId)
        else {
            Haptics.warning()
            return
        }
        Haptics.tap()
        let vc = CommunityOrLoadingViewController(
            communityName: row.communityName,
            instance: instance,
            accountKeychainId: viewModel.accountKeychainId,
            dependencies: dependencies.nested
        )
        navigationController?.pushViewController(vc, animated: true)
    }

    /// Pushes the post author's profile screen. Browsing is allowed
    /// signed-out, so this is not gated.
    private func viewAuthor(serverPostId: Int64) {
        guard
            let row = rowsByServerPostId[serverPostId],
            let actorId = row.creatorActorId,
            let instance = InstanceActorId(from: actorId)
        else {
            Haptics.warning()
            return
        }
        Haptics.tap()
        let vc = PersonOrLoadingViewController(
            personId: Components.Schemas.PersonID(row.creatorPersonId),
            instance: instance,
            accountKeychainId: viewModel.accountKeychainId,
            dependencies: dependencies.nested
        )
        navigationController?.pushViewController(vc, animated: true)
    }

    /// Reports the post, gating on sign-in. Mirrors the post-detail report
    /// flow: a required-reason alert, then a confirmation.
    private func reportPost(serverPostId: Int64) {
        guard !accountService.isSignedOut(forAccountKeychainId: viewModel.accountKeychainId) else {
            presentSignInGate(
                title: NSLocalizedString("Sign in to report", comment: "Sign-in gate title when a signed-out user tries to report")
            )
            return
        }
        presentReportReasonAlert(
            title: NSLocalizedString("Report post", comment: "Report post dialog title"),
            message: NSLocalizedString("Tell the moderators why you're reporting this post.", comment: "Report post dialog message")
        ) { [weak self] reason in
            Task { await self?.submitPostReport(serverPostId: serverPostId, reason: reason) }
        }
    }

    private func submitPostReport(serverPostId: Int64, reason: String) async {
        Haptics.tap()
        do {
            try await accountService
                .lemmyService(forAccountKeychainId: viewModel.accountKeychainId)
                .reportPost(serverPostId: Components.Schemas.PostID(serverPostId), reason: reason)
            Haptics.success()
            presentReportSubmittedConfirmation()
        } catch {
            alertService.handle(error, for: .reportPost)
        }
    }

    /// Blocks the post's author, gating on sign-in and confirming first. The
    /// server filters blocked authors from later feed fetches, so their posts
    /// drop out on the next refresh.
    private func blockAuthor(serverPostId: Int64) {
        guard !accountService.isSignedOut(forAccountKeychainId: viewModel.accountKeychainId) else {
            presentSignInGate(
                title: NSLocalizedString("Sign in to block", comment: "Sign-in gate title when a signed-out user tries to block")
            )
            return
        }
        guard let row = rowsByServerPostId[serverPostId] else { return }
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
            Task { await self?.submitBlockAuthor(serverPersonId: row.creatorPersonId) }
        }
    }

    private func submitBlockAuthor(serverPersonId: Int64) async {
        do {
            try await accountService
                .lemmyService(forAccountKeychainId: viewModel.accountKeychainId)
                .setBlocked(serverPersonId: Components.Schemas.PersonID(serverPersonId), blocked: true)
        } catch {
            alertService.handle(error, for: .setBlockedPerson)
        }
    }

    /// Hides the post, gating on sign-in. The hidden flag is server-backed; on
    /// success the GRDB observation re-emits without the row, so it drops out of
    /// the feed.
    private func hidePost(serverPostId: Int64) {
        guard !accountService.isSignedOut(forAccountKeychainId: viewModel.accountKeychainId) else {
            presentSignInGate(
                title: NSLocalizedString("Sign in to hide posts", comment: "Sign-in gate title when a signed-out user tries to hide a post")
            )
            return
        }
        Task { await performHidePost(serverPostId: serverPostId) }
    }

    private func performHidePost(serverPostId: Int64) async {
        Haptics.tap()
        do {
            try await accountService
                .lemmyService(forAccountKeychainId: viewModel.accountKeychainId)
                .hidePost(serverPostId: Components.Schemas.PostID(serverPostId), hidden: true)
        } catch {
            alertService.handle(error, for: .hidePost)
        }
    }

    /// The "Mute <community> >" submenu offering the timed durations. Muting is
    /// a local view concern, so it isn't sign-in gated.
    private func makeMuteCommunityMenu(serverPostId: Int64, communityName: String) -> UIMenu {
        let actions = MuteDuration.allCases.map { duration in
            UIAction(title: duration.menuTitle) { [weak self] _ in
                self?.muteCommunity(serverPostId: serverPostId, duration: duration)
            }
        }
        return UIMenu(
            title: String(format: NSLocalizedString("Mute %@", comment: "Context-menu action to mute a community; %@ is the c/ community handle"), "c/\(communityName)"),
            image: UIImage(systemName: "bell.slash"),
            children: actions
        )
    }

    private func muteCommunity(serverPostId: Int64, duration: MuteDuration) {
        guard
            let row = rowsByServerPostId[serverPostId],
            let actorId = row.communityActorId
        else {
            Haptics.warning()
            return
        }
        Haptics.tap()
        appDatabase.muteCommunitySync(
            forKeychainId: viewModel.accountKeychainId,
            communityActorId: actorId,
            until: duration.until
        )
    }

    private func vote(serverPostId: Int64, action: VoteStatus.Action) async {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        do {
            try await accountService
                .lemmyService(forAccountKeychainId: viewModel.accountKeychainId)
                .vote(serverPostId: Components.Schemas.PostID(serverPostId), vote: action)
        } catch {
            alertService.handle(error, for: .vote)
        }
    }

    /// Toggles the saved state for `serverPostId` against its currently
    /// observed value, gating on sign-in.
    private func toggleSaved(serverPostId: Int64) {
        let keychainId = viewModel.accountKeychainId
        guard !accountService.isSignedOut(forAccountKeychainId: keychainId) else {
            presentSignInGate(
                title: NSLocalizedString("Sign in to save", comment: "Sign-in gate title when a signed-out user tries to save a post")
            )
            return
        }

        let currentlySaved = rowsByServerPostId[serverPostId]?.isSaved ?? false
        Task { await setSaved(serverPostId: serverPostId, saved: !currentlySaved) }
    }

    private func setSaved(serverPostId: Int64, saved: Bool) async {
        Haptics.tap()
        do {
            try await accountService
                .lemmyService(forAccountKeychainId: viewModel.accountKeychainId)
                .setSaved(serverPostId: Components.Schemas.PostID(serverPostId), saved: saved)
        } catch {
            alertService.handle(error, for: .save)
        }
    }

    /// Shares the post's canonical URL. Prefers the post's `ap_id` permalink;
    /// falls back to constructing it from the account instance.
    private func sharePost(serverPostId: Int64) {
        let instanceActorId = appDatabase.accountInstanceActorIdSync(
            forKeychainId: viewModel.accountKeychainId
        )
        guard let url = ShareURL.forPost(
            originalPostUrl: rowsByServerPostId[serverPostId]?.originalPostUrl,
            serverPostId: serverPostId,
            instanceActorId: instanceActorId
        ) else {
            Haptics.warning()
            return
        }
        presentShareSheet(for: url)
    }

    private func postSelected(serverPostId: Int64) {
        guard let window = view.window as? MainWindow else { fatalError() }
        window.display(
            serverPostId: Components.Schemas.PostID(serverPostId),
            accountKeychainId: viewModel.accountKeychainId
        )
    }

    private func presentMediaViewer(
        imageUrl: URL,
        thumbnailUrl: URL?,
        preloadedImage: UIImage?,
        altText: String? = nil
    ) {
        let item = MediaItem(
            imageUrl: imageUrl,
            thumbnailUrl: thumbnailUrl,
            preloadedImage: preloadedImage,
            altText: altText
        )
        let viewer = MediaViewerViewController.make(
            items: [item],
            dependencies: dependencies.own
        )
        present(viewer, animated: true)
    }

    private func donateIntent() {
        let intent = ViewTopPostsIntent()

        let feed = viewModel.feed
        guard let feedType = IntentFeedType(from: feed.feedType) else { return }

        intent.feedType = feedType
        intent.sortType = .init(from: feed.feedType.sortType)

        logger.debug("Donating intent \(intent, privacy: .public)")

        let interaction = INInteraction(intent: intent, response: nil)
        interaction.donate { error in
            if let error {
                logger.error("Failed to donate intent: \(error, privacy: .public)")
            }
        }
    }
}

// MARK: - UITableView Delegate

extension PostListViewController: UITableViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let position = scrollView.contentOffset.y + scrollView.bounds.height
        let totalHeight = scrollView.contentSize.height
        guard totalHeight > 0 else { return }
        let verticalFraction = position / totalHeight
        if verticalFraction > 0.9 {
            viewModel.didScrollToBottom()
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard case let .post(serverPostId) = dataSource.itemIdentifier(for: indexPath) else { return }
        postSelected(serverPostId: serverPostId)
    }

    /// Marks a post read as it scrolls out of view, when the
    /// mark-read-on-scroll preference is on. Best-effort: it updates the local
    /// read state (which flows back through the GRDB observation) and fires the
    /// server call without surfacing failures.
    func tableView(
        _ tableView: UITableView,
        didEndDisplaying cell: UITableViewCell,
        forRowAt indexPath: IndexPath
    ) {
        guard markPostsRead, markPostsReadOnScroll else { return }
        // The cell has already left the data source's reach by the time this
        // fires after a snapshot apply, so resolve the post id from the cell's
        // last-known item rather than `itemIdentifier(for:)`.
        guard let item = dataSource.itemIdentifier(for: indexPath),
              case let .post(serverPostId) = item else { return }
        markReadOnScroll(serverPostId: serverPostId)
    }

    private func markReadOnScroll(serverPostId: Int64) {
        // Skip rows already read or already enqueued this session.
        guard !scrollMarkedReadIds.contains(serverPostId) else { return }
        if rowsByServerPostId[serverPostId]?.isRead == true {
            scrollMarkedReadIds.insert(serverPostId)
            return
        }
        scrollMarkedReadIds.insert(serverPostId)

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await accountService
                    .lemmyService(forAccountKeychainId: viewModel.accountKeychainId)
                    .markAsRead(serverPostId: Components.Schemas.PostID(serverPostId))
            } catch {
                // Best-effort: a failed scroll mark-read should not interrupt
                // browsing. Allow a later retry by un-enqueuing.
                scrollMarkedReadIds.remove(serverPostId)
                logger.debug("Scroll mark-as-read failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    // MARK: Context Menu

    func tableView(
        _ tableView: UITableView,
        previewForHighlightingContextMenuWithConfiguration configuration: UIContextMenuConfiguration
    ) -> UITargetedPreview? {
        guard let indexPath = configuration.identifier as? IndexPath else { fatalError() }
        guard let cell = tableView.cellForRow(at: indexPath) else { return nil }
        guard let cell = cell as? PostListPostCell else { fatalError() }

        let parameters = UIPreviewParameters()
        parameters.backgroundColor = .clear
        parameters.visiblePath = UIBezierPath(roundedRect: cell.bounds, cornerRadius: 12)

        return UITargetedPreview(view: cell, parameters: parameters)
    }

    func tableView(
        _ tableView: UITableView,
        willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration,
        animator: UIContextMenuInteractionCommitAnimating
    ) {
        guard
            let indexPath = configuration.identifier as? IndexPath,
            case let .post(serverPostId) = dataSource.itemIdentifier(for: indexPath)
        else { return }
        postSelected(serverPostId: serverPostId)
    }

    /// The floating peek shown above the post's context menu: image, title and
    /// full body (the feed truncates the body). Returns nil for a missing row.
    private func postPreviewViewController(at indexPath: IndexPath) -> UIViewController? {
        guard
            case let .post(serverPostId) = dataSource.itemIdentifier(for: indexPath),
            let row = rowsByServerPostId[serverPostId]
        else { return nil }

        return PostPreviewViewController(
            row: row,
            imageService: imageService,
            postContentDetector: dependencies.own.postContentDetectorService,
            textSizeAdjustment: appearanceService.postDetail.textSizeAdjustment
        )
    }

    func tableView(
        _ tableView: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        let generalAppearance = appearanceService.general
        return UIContextMenuConfiguration(
            identifier: indexPath as NSCopying,
            previewProvider: { [weak self] in self?.postPreviewViewController(at: indexPath) },
            actionProvider: { [weak self] _ in
                guard
                    case let .post(serverPostId) = self?.dataSource.itemIdentifier(for: indexPath)
                else { return nil }

                let upvoteAction = UIAction(
                    title: NSLocalizedString("Upvote", comment: ""),
                    image: generalAppearance.upvoteIcon
                ) { [weak self] _ in
                    Task { await self?.vote(serverPostId: serverPostId, action: .upvote) }
                }

                let downvoteAction = UIAction(
                    title: NSLocalizedString("Downvote", comment: ""),
                    image: generalAppearance.downvoteIcon
                ) { [weak self] _ in
                    Task { await self?.vote(serverPostId: serverPostId, action: .downvote) }
                }

                let isSaved = self?.rowsByServerPostId[serverPostId]?.isSaved ?? false
                let saveAction = UIAction(
                    title: isSaved
                        ? NSLocalizedString("Unsave", comment: "Context-menu action to unsave a post")
                        : NSLocalizedString("Save", comment: "Context-menu action to save a post"),
                    image: UIImage(systemName: isSaved ? "bookmark.slash" : "bookmark")
                ) { [weak self] _ in
                    self?.toggleSaved(serverPostId: serverPostId)
                }

                let replyAction = UIAction(
                    title: NSLocalizedString("Reply", comment: "Context-menu action to reply to a post"),
                    image: UIImage(systemName: "arrowshape.turn.up.left")
                ) { [weak self] _ in
                    self?.replyToPost(serverPostId: serverPostId)
                }

                let shareAction = UIAction(
                    title: NSLocalizedString("Share", comment: "Context-menu action to share a post"),
                    image: UIImage(systemName: "square.and.arrow.up")
                ) { [weak self] _ in
                    self?.sharePost(serverPostId: serverPostId)
                }

                let row = self?.rowsByServerPostId[serverPostId]

                let visitCommunityAction = UIAction(
                    title: String(
                        format: NSLocalizedString("Visit %@", comment: "Context-menu action to open a post's community; %@ is the c/ community handle"),
                        row?.communityName.map { "c/\($0)" } ?? NSLocalizedString("community", comment: "Generic community noun")
                    ),
                    image: UIImage(systemName: "person.3")
                ) { [weak self] _ in
                    self?.visitCommunity(serverPostId: serverPostId)
                }

                let viewAuthorAction = UIAction(
                    title: row?.creatorName.map {
                        String(format: NSLocalizedString("View %@", comment: "Context-menu action to open a post author's profile; %@ is the u/ author handle"), "u/\($0)")
                    } ?? NSLocalizedString("View author", comment: "Context-menu action to open a post author's profile"),
                    image: UIImage(systemName: "person.crop.circle")
                ) { [weak self] _ in
                    self?.viewAuthor(serverPostId: serverPostId)
                }

                let hideAction = UIAction(
                    title: NSLocalizedString("Hide", comment: "Context-menu action to hide a post from the feed"),
                    image: UIImage(systemName: "eye.slash")
                ) { [weak self] _ in
                    self?.hidePost(serverPostId: serverPostId)
                }

                let blockAction = UIAction(
                    title: row?.creatorName.map {
                        String(format: NSLocalizedString("Block %@", comment: "Context-menu action to block a post author; %@ is the u/ author handle"), "u/\($0)")
                    } ?? NSLocalizedString("Block author", comment: "Context-menu action to block a post author"),
                    image: UIImage(systemName: "hand.raised"),
                    attributes: .destructive
                ) { [weak self] _ in
                    self?.blockAuthor(serverPostId: serverPostId)
                }

                let reportAction = UIAction(
                    title: NSLocalizedString("Report", comment: "Context-menu action to report a post"),
                    image: UIImage(systemName: "flag"),
                    attributes: .destructive
                ) { [weak self] _ in
                    self?.reportPost(serverPostId: serverPostId)
                }

                // Grouped with inline submenus so each renders with a divider,
                // matching the design's long-press menu layout.
                let voteGroup = UIMenu(options: .displayInline, children: [upvoteAction, downvoteAction, saveAction])
                let shareGroup = UIMenu(options: .displayInline, children: [replyAction, shareAction])
                let navGroup = UIMenu(options: .displayInline, children: [visitCommunityAction, viewAuthorAction])
                var hideChildren: [UIMenuElement] = [hideAction]
                if let self, let communityName = row?.communityName, !communityName.isEmpty, row?.communityActorId != nil {
                    hideChildren.append(makeMuteCommunityMenu(serverPostId: serverPostId, communityName: communityName))
                }
                let hideGroup = UIMenu(options: .displayInline, children: hideChildren)
                let safetyGroup = UIMenu(options: .displayInline, children: [blockAction, reportAction])

                var children: [UIMenuElement] = [voteGroup, shareGroup, navGroup, hideGroup]
                // Moderation submenu, only when the account moderates this
                // post's community (or is an admin).
                if let modMenu = self?.postModerationMenu(serverPostId: serverPostId) {
                    children.append(modMenu)
                }
                children.append(safetyGroup)
                return UIMenu(title: "", children: children)
            }
        )
    }

    // MARK: Moderation

    /// The moderation menu for the post at `serverPostId`, or nil when the
    /// account cannot moderate its community. Offers Remove/Restore,
    /// Lock/Unlock, Pin to community, and (admins) Pin to instance.
    private func postModerationMenu(serverPostId: Int64) -> UIMenu? {
        guard let row = rowsByServerPostId[serverPostId] else { return nil }
        let communityId = Components.Schemas.CommunityID(row.serverCommunityId)
        guard moderationCapability.canModerate(communityId: communityId) else { return nil }

        let postId = Components.Schemas.PostID(serverPostId)
        var children: [UIMenuElement] = []

        if row.isRemoved {
            children.append(UIAction(
                title: NSLocalizedString("Restore", comment: "Mod action: restore a removed post"),
                image: UIImage(systemName: "arrow.uturn.backward")
            ) { [weak self] _ in
                self?.performRemovePost(serverPostId: postId, removed: false)
            })
        } else {
            children.append(UIAction(
                title: NSLocalizedString("Remove", comment: "Mod action: remove a post"),
                image: UIImage(systemName: "trash.slash"),
                attributes: .destructive
            ) { [weak self] _ in
                self?.promptRemovePost(serverPostId: postId)
            })
        }

        let locked = row.isLocked
        children.append(UIAction(
            title: locked
                ? NSLocalizedString("Unlock", comment: "Mod action: unlock a post")
                : NSLocalizedString("Lock", comment: "Mod action: lock a post"),
            image: UIImage(systemName: locked ? "lock.open" : "lock")
        ) { [weak self] _ in
            self?.performLockPost(serverPostId: postId, locked: !locked)
        })

        let featuredCommunity = row.isFeaturedCommunity
        children.append(UIAction(
            title: featuredCommunity
                ? NSLocalizedString("Unpin from community", comment: "Mod action: unfeature post in community")
                : NSLocalizedString("Pin to community", comment: "Mod action: feature post in community"),
            image: UIImage(systemName: featuredCommunity ? "pin.slash" : "pin")
        ) { [weak self] _ in
            self?.performFeaturePost(serverPostId: postId, featured: !featuredCommunity, local: false)
        })

        if moderationCapability.isAdmin {
            let featuredLocal = row.isFeaturedLocal
            children.append(UIAction(
                title: featuredLocal
                    ? NSLocalizedString("Unpin from instance", comment: "Admin action: unfeature post on instance")
                    : NSLocalizedString("Pin to instance", comment: "Admin action: feature post on instance"),
                image: UIImage(systemName: featuredLocal ? "pin.slash.fill" : "pin.fill")
            ) { [weak self] _ in
                self?.performFeaturePost(serverPostId: postId, featured: !featuredLocal, local: true)
            })
        }

        return UIMenu(
            title: NSLocalizedString("Moderation", comment: "Moderation submenu title"),
            image: UIImage(systemName: "shield"),
            children: children
        )
    }

    private func promptRemovePost(serverPostId: Components.Schemas.PostID) {
        presentModerationReasonAlert(
            title: NSLocalizedString("Remove post", comment: "Remove post dialog title"),
            message: NSLocalizedString("Optionally tell the author why the post was removed.", comment: "Remove post dialog message"),
            submitTitle: NSLocalizedString("Remove", comment: "Remove alert submit button")
        ) { [weak self] reason in
            self?.performRemovePost(serverPostId: serverPostId, removed: true, reason: reason)
        }
    }

    private func performRemovePost(
        serverPostId: Components.Schemas.PostID,
        removed: Bool,
        reason: String? = nil
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            Haptics.tap()
            do {
                try await accountService
                    .lemmyService(forAccountKeychainId: viewModel.accountKeychainId)
                    .removePost(serverPostId: serverPostId, removed: removed, reason: reason)
                Haptics.success()
            } catch {
                alertService.handle(error, for: .removePost)
            }
        }
    }

    private func performLockPost(serverPostId: Components.Schemas.PostID, locked: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            Haptics.tap()
            do {
                try await accountService
                    .lemmyService(forAccountKeychainId: viewModel.accountKeychainId)
                    .lockPost(serverPostId: serverPostId, locked: locked)
                Haptics.success()
            } catch {
                alertService.handle(error, for: .lockPost)
            }
        }
    }

    private func performFeaturePost(
        serverPostId: Components.Schemas.PostID,
        featured: Bool,
        local: Bool
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            Haptics.tap()
            do {
                try await accountService
                    .lemmyService(forAccountKeychainId: viewModel.accountKeychainId)
                    .featurePost(serverPostId: serverPostId, featured: featured, local: local)
                Haptics.success()
            } catch {
                alertService.handle(error, for: .featurePost)
            }
        }
    }
}

// MARK: - UITableViewDataSourcePrefetching

extension PostListViewController: UITableViewDataSourcePrefetching {
    /// Warms the image cache for image posts a few rows ahead of the visible
    /// window, so the thumbnail is already decoded by the time the cell is
    /// configured — no pop-in while scrolling quickly. The cell's own fetch then
    /// resolves from the cache. Text/link posts have nothing to prefetch.
    func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
        let imageService = imageService
        let postContentDetector = dependencies.own.postContentDetectorService
        for indexPath in indexPaths {
            guard case let .post(serverPostId) = dataSource.itemIdentifier(for: indexPath) else { continue }
            guard prefetchTasks[serverPostId] == nil else { continue }
            guard let row = rowsByServerPostId[serverPostId] else { continue }
            guard let url = PostListPostViewModel.prefetchThumbnailUrl(
                for: row,
                postContentDetector: postContentDetector
            ) else { continue }

            // Match the cell's downsample target so the prefetch warms the same
            // cache entry the cell reads.
            let size = CGSize(width: PostListPostCell.thumbnailDimension, height: PostListPostCell.thumbnailDimension)
            prefetchTasks[serverPostId] = Task { [weak self] in
                for await state in imageService.fetch(url, downsampleTo: size) {
                    if Task.isCancelled { break }
                    // Stop once the fetch settles; .loading just means in flight.
                    if case .loading = state { continue }
                    break
                }
                self?.prefetchTasks[serverPostId] = nil
            }
        }
    }

    func tableView(_ tableView: UITableView, cancelPrefetchingForRowsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            guard case let .post(serverPostId) = dataSource.itemIdentifier(for: indexPath) else { continue }
            prefetchTasks[serverPostId]?.cancel()
            prefetchTasks[serverPostId] = nil
        }
    }
}

/// Re-tracks an Observable property after each onChange tick and yields
/// the latest value into the supplied AsyncStream.Continuation. Decoupling
/// `observe()` into an instance method dodges the "non-Sendable local
/// function captured in @Sendable closure" warning that arises when
/// `withObservationTracking`'s onChange recurses into a @MainActor func.
@MainActor
private final class ObservationScheduler<Value: Sendable>: Sendable {
    private let continuation: AsyncStream<Value>.Continuation
    private let access: @MainActor () -> Value

    init(
        continuation: AsyncStream<Value>.Continuation,
        access: @escaping @MainActor () -> Value
    ) {
        self.continuation = continuation
        self.access = access
    }

    func observe() {
        let value = withObservationTracking {
            access()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
        continuation.yield(value)
    }
}
