//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudDataKit
import SpudUIKit
import SpudUtilKit
import UIKit

@MainActor
class ActivityViewController: UIViewController {
    typealias OwnDependencies =
        HasAccountService &
        HasAlertService &
        HasAppDatabase &
        HasAppService &
        HasAppearanceService &
        HasImageService &
        HasPostContentDetectorService &
        HasPreferencesService
    typealias NestedDependencies = PostDetailViewController.Dependencies
    typealias Dependencies = NestedDependencies & OwnDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    var accountService: AccountServiceType {
        dependencies.own.accountService
    }

    var alertService: AlertServiceType {
        dependencies.own.alertService
    }

    var appDatabase: AppDatabase {
        dependencies.own.appDatabase
    }

    var appService: AppServiceType {
        dependencies.own.appService
    }

    var appearanceService: AppearanceServiceType {
        dependencies.own.appearanceService
    }

    var imageService: ImageServiceType {
        dependencies.own.imageService
    }

    var postContentDetector: PostContentDetectorServiceType {
        dependencies.own.postContentDetectorService
    }

    var preferencesService: PreferencesServiceType {
        dependencies.own.preferencesService
    }

    // MARK: Private

    /// Below this many items, a `.vote`-filtered timeline shows the
    /// "Votes start filling in now" banner so a sparse first run reads as
    /// expected (forward-only capture), not broken.
    private static let votedSparseThreshold = 5

    private let accountKeychainId: String
    private let accountId: Int64
    private let personRowId: Int64?
    private let viewModel: ActivityViewModel

    private var observationTask: Task<Void, Never>?
    private var displayPrefsObservationTasks: [Task<Void, Never>] = []

    /// Posts whose NSFW thumbnail the user revealed this session (by server post
    /// id). Not persisted; resets on relaunch. Mirrors the feed / Person screen.
    private var revealedNsfwPostIds: Set<Int64> = []

    // MARK: UI

    private lazy var filterBarView: ActivityFilterBarView = {
        let v = ActivityFilterBarView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.onToggleFilter = { [weak self] filter in
            self?.viewModel.toggleFilter(filter)
        }
        v.onResetFilters = { [weak self] in
            self?.viewModel.resetFilters()
        }
        return v
    }()

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.rowHeight = UITableView.automaticDimension
        tv.estimatedRowHeight = 120
        tv.delegate = self
        tv.refreshControl = refreshControl
        tv.register(ActivityPostRowCell.self, forCellReuseIdentifier: ActivityPostRowCell.reuseIdentifier)
        tv.register(ActivityCommentRowCell.self, forCellReuseIdentifier: ActivityCommentRowCell.reuseIdentifier)
        tv.register(UITableViewHeaderFooterView.self, forHeaderFooterViewReuseIdentifier: Self.headerReuseIdentifier)
        return tv
    }()

    private lazy var refreshControl: UIRefreshControl = {
        let control = UIRefreshControl()
        control.addTarget(self, action: #selector(refreshTriggered), for: .valueChanged)
        return control
    }()

    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()

    // MARK: Banner (offline / sparse)

    private lazy var bannerLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .preferredFont(forTextStyle: .footnote)
        l.adjustsFontForContentSizeCategory = true
        l.textColor = .secondaryLabel
        l.numberOfLines = 0
        return l
    }()

    private lazy var bannerButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 0)
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.addAction(UIAction { [weak self] _ in self?.bannerAction?() }, for: .touchUpInside)
        return button
    }()

    /// Invoked when the banner's trailing button is tapped (e.g. Retry). Cleared
    /// when the banner has no action (the button is hidden).
    private var bannerAction: (() -> Void)?

    private lazy var bannerView: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = .secondarySystemBackground
        container.isHidden = true

        let stack = UIStackView(arrangedSubviews: [bannerLabel, bannerButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
        ])
        return container
    }()

    private lazy var searchController: UISearchController = {
        let sc = UISearchController(searchResultsController: nil)
        sc.searchResultsUpdater = self
        sc.obscuresBackgroundDuringPresentation = false
        sc.searchBar.placeholder = NSLocalizedString("Search activity", comment: "Activity search bar placeholder")
        return sc
    }()

    private static let headerReuseIdentifier = "ActivityDaySectionHeader"

    private var dataSource: UITableViewDiffableDataSource<String, String>!

    // MARK: Lookup

    private var itemById: [String: ActivityItem] = [:]

    // MARK: Functions

    /// Creates an ActivityViewController.
    ///
    /// - Parameters:
    ///   - accountKeychainId: The keychain id of the signed-in account whose activity is shown.
    ///   - initialFilters: The filter chips that should be active when the screen first opens.
    ///     Pass an empty set (the default) to show all activity types.
    ///   - dependencies: Dependency container.
    init(
        accountKeychainId: String,
        initialFilters: Set<ActivityFilterType> = [],
        dependencies: Dependencies
    ) {
        self.accountKeychainId = accountKeychainId
        self.dependencies = (own: dependencies, nested: dependencies)

        let db = dependencies.appDatabase
        let serverPersonId = db.accountPersonServerIdSync(forKeychainId: accountKeychainId)
        let resolvedPersonRowId = serverPersonId.flatMap {
            db.personRowIdSync(forKeychainId: accountKeychainId, personId: $0)
        }
        let lemmyService = dependencies.accountService.scope(forAccountKeychainId: accountKeychainId).lemmyService
        let authoredSource: AuthoredActivitySource? = serverPersonId.map {
            LemmyAuthoredActivitySource(
                lemmyService: lemmyService,
                serverPersonId: Components.Schemas.PersonID($0)
            )
        }
        let coordinator = ActivityCoordinator(
            appDatabase: db,
            personRowId: resolvedPersonRowId,
            authoredSource: authoredSource
        )
        let resolvedAccountId = db.accountRowIdSync(forKeychainId: accountKeychainId) ?? 0
        accountId = resolvedAccountId
        personRowId = resolvedPersonRowId
        viewModel = ActivityViewModel(coordinator: coordinator, accountId: resolvedAccountId, initialFilters: initialFilters)

        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        observationTask?.cancel()
        for task in displayPrefsObservationTasks {
            task.cancel()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        title = NSLocalizedString("Activity", comment: "Activity screen title")
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = true
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: NSLocalizedString("Summary", comment: "Activity nav bar Summary button"),
            style: .plain,
            target: self,
            action: #selector(summaryButtonTapped)
        )

        setupLayout()
        setupDataSource()
        startObservation()
        startDisplayObservations()
        viewModel.start()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Belt-and-suspenders teardown of the coordinator streams when the screen
        // leaves the hierarchy (the view model's deinit also covers this).
        if isMovingFromParent || isBeingDismissed {
            viewModel.stop()
        }
    }

    // MARK: Private

    private func setupLayout() {
        let filterContainer = UIView()
        filterContainer.translatesAutoresizingMaskIntoConstraints = false
        filterContainer.addSubview(filterBarView)

        NSLayoutConstraint.activate([
            filterBarView.leadingAnchor.constraint(equalTo: filterContainer.leadingAnchor),
            filterBarView.trailingAnchor.constraint(equalTo: filterContainer.trailingAnchor),
            filterBarView.topAnchor.constraint(equalTo: filterContainer.topAnchor),
            filterBarView.bottomAnchor.constraint(equalTo: filterContainer.bottomAnchor),
            filterContainer.heightAnchor.constraint(equalToConstant: 50),
        ])

        tableView.tableHeaderView = filterContainer

        // A vertical layout: an optional banner (offline / sparse) above the
        // scrolling timeline. The banner collapses (zero height) when hidden.
        let stack = UIStackView(arrangedSubviews: [bannerView, tableView])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical

        view.addSubview(stack)
        view.addSubview(loadingIndicator)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            loadingIndicator.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),
        ])
    }

    private func setupDataSource() {
        dataSource = UITableViewDiffableDataSource<String, String>(
            tableView: tableView
        ) { [weak self] tableView, indexPath, itemId in
            self?.cell(tableView: tableView, indexPath: indexPath, itemId: itemId)
        }
        dataSource.defaultRowAnimation = .fade
    }

    private func cell(
        tableView: UITableView,
        indexPath: IndexPath,
        itemId: String
    ) -> UITableViewCell {
        guard let item = itemById[itemId] else {
            return UITableViewCell()
        }
        switch item.object {
        case let .post(post):
            return makePostCell(tableView, indexPath: indexPath, item: item, row: post)
        case let .comment(comment):
            return makeCommentCell(tableView, indexPath: indexPath, item: item, comment: comment)
        }
    }

    /// Configures the reused `PostListPostContentView` (inside the action-header
    /// container) exactly as the feed / Person screen do: the same view model,
    /// callbacks (vote / media / reveal), so a post row looks and behaves like a
    /// feed row.
    private func makePostCell(
        _ tableView: UITableView,
        indexPath: IndexPath,
        item: ActivityItem,
        row: PostListRow
    ) -> UITableViewCell {
        let container = tableView.dequeueReusableCell(
            withIdentifier: ActivityPostRowCell.reuseIdentifier,
            for: indexPath
        ) as! ActivityPostRowCell

        let serverPostId = row.serverPostId
        let cellViewModel = PostListPostViewModel(
            row: row,
            appearance: appearanceService,
            postContentDetector: postContentDetector,
            blurNsfw: preferencesService.blurNsfw,
            isRevealed: revealedNsfwPostIds.contains(serverPostId)
        )
        container.postContentView.configure(with: cellViewModel, imageService: imageService)
        container.configure(
            item: item,
            postSummary: cellViewModel.accessibilityLabel,
            hint: cellViewModel.accessibilityHint
        )

        container.postContentView.revealNsfwTapped = { [weak self] in
            guard let self else { return }
            revealedNsfwPostIds.insert(serverPostId)
            reconfigureVisibleItems()
        }
        container.postContentView.imageTapped = { [weak self] imageUrl, thumbnailUrl, thumbnailImage in
            guard let self else { return }
            presentMediaViewer(
                imageUrl: imageUrl,
                thumbnailUrl: thumbnailUrl,
                preloadedImage: thumbnailImage,
                altText: row.altText,
                isNsfw: row.isNsfw,
                dependencies: dependencies.own
            )
        }
        container.postContentView.videoTapped = { [weak self] videoUrl in
            self?.presentVideoPlayer(url: videoUrl)
        }
        container.postContentView.linkTapped = { [weak self] linkUrl in
            self?.openExternalLink(linkUrl)
        }
        container.postContentView.voteTapped = { [weak self] action in
            guard let self else { return }
            Task { await self.vote(serverPostId: serverPostId, action: action) }
        }
        return container
    }

    private func makeCommentCell(
        _ tableView: UITableView,
        indexPath: IndexPath,
        item: ActivityItem,
        comment: ActivityCommentRow
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: ActivityCommentRowCell.reuseIdentifier,
            for: indexPath
        ) as! ActivityCommentRowCell
        // A voted comment that isn't in the local cache has no parent post id, so
        // it can't be opened (Phase-1 limitation; see account-activity.md).
        let hint = comment.serverPostId == nil
            ? NSLocalizedString(
                "This comment isn't available to open",
                comment: "Activity VoiceOver hint: a snapshot-only comment can't be tapped through"
            )
            : NSLocalizedString(
                "Opens the comment in its post",
                comment: "Activity VoiceOver hint for a comment row"
            )
        cell.configure(item: item, comment: comment, hint: hint)
        return cell
    }

    private func startObservation() {
        observationTask?.cancel()
        let viewModel = viewModel
        observationTask = Task { @MainActor [weak self] in
            for await _ in ObservationStream.values(of: {
                (viewModel.items, viewModel.activeFilters, viewModel.loadState)
            }) {
                if Task.isCancelled { break }
                self?.applySnapshot()
            }
        }
    }

    /// Observes the display preferences that feed `PostListPostViewModel`
    /// (density, thumbnail position, text scale, vote-button visibility, accent),
    /// so the timeline honors the user's display-density setting live, mirroring
    /// the feed. Each stream replays its current value, so the first element is
    /// skipped (the cells already reflect it).
    private func startDisplayObservations() {
        let preferencesService = preferencesService

        displayPrefsObservationTasks.append(Task { @MainActor [weak self] in
            var first = true
            for await _ in preferencesService.postDensityStream {
                if Task.isCancelled { break }
                if first { first = false
                    continue
                }
                self?.reconfigureVisibleItems()
            }
        })
        displayPrefsObservationTasks.append(Task { @MainActor [weak self] in
            var first = true
            for await _ in preferencesService.thumbnailPositionStream {
                if Task.isCancelled { break }
                if first { first = false
                    continue
                }
                self?.reconfigureVisibleItems()
            }
        })
        displayPrefsObservationTasks.append(Task { @MainActor [weak self] in
            var first = true
            for await _ in preferencesService.postTextScaleStream {
                if Task.isCancelled { break }
                if first { first = false
                    continue
                }
                self?.reconfigureVisibleItems()
            }
        })
        displayPrefsObservationTasks.append(Task { @MainActor [weak self] in
            var first = true
            for await _ in preferencesService.showVoteButtonsStream {
                if Task.isCancelled { break }
                if first { first = false
                    continue
                }
                self?.reconfigureVisibleItems()
            }
        })
        displayPrefsObservationTasks.append(Task { @MainActor [weak self] in
            var first = true
            for await _ in preferencesService.accentColorStream {
                if Task.isCancelled { break }
                if first { first = false
                    continue
                }
                self?.reconfigureVisibleItems()
            }
        })
    }

    private func applySnapshot() {
        let items = viewModel.items

        itemById = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        filterBarView.activeFilters = viewModel.activeFilters

        let grouped = groupedByDay(items)
        var snapshot = NSDiffableDataSourceSnapshot<String, String>()
        for (section, sectionItems) in grouped {
            snapshot.appendSections([section])
            snapshot.appendItems(sectionItems.map(\.id), toSection: section)
        }
        // A GRDB re-emission that only changes a row's data (vote, save, read)
        // keeps the same item id, so reconfigure survivors in place. Matches the
        // feed's `apply(rows:)`.
        snapshot.reconfigureItems(snapshot.itemIdentifiers)
        dataSource.apply(snapshot, animatingDifferences: true)

        updateStates()
    }

    /// Reconfigures the on-screen rows in place (e.g. after a display-preference
    /// change or an NSFW reveal) without animating a diff.
    private func reconfigureVisibleItems() {
        guard dataSource != nil else { return }
        let visible = (tableView.indexPathsForVisibleRows ?? [])
            .compactMap { dataSource.itemIdentifier(for: $0) }
        guard !visible.isEmpty else { return }
        var snapshot = dataSource.snapshot()
        snapshot.reconfigureItems(visible)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    // MARK: States

    /// Renders the empty / loading / offline / sparse states off the coordinator's
    /// already-computed `items` + `loadState` (see `ActivityLoadState`).
    private func updateStates() {
        let items = viewModel.items
        let state = viewModel.loadState
        let filters = viewModel.activeFilters

        // First-load spinner only: once any items exist (or the load settles)
        // the spinner gives way to content or an empty/offline state.
        let isInitialLoading = items.isEmpty && state == .loading
        if isInitialLoading {
            loadingIndicator.startAnimating()
        } else {
            loadingIndicator.stopAnimating()
        }

        if refreshControl.isRefreshing, state != .loading {
            refreshControl.endRefreshing()
        }

        updateBanner(state: state, filters: filters, itemCount: items.count)

        if items.isEmpty, !isInitialLoading {
            tableView.backgroundView = emptyBackgroundView(filters: filters)
        } else {
            tableView.backgroundView = nil
        }
    }

    private func updateBanner(state: ActivityLoadState, filters: Set<ActivityFilterType>, itemCount: Int) {
        if state == .degraded {
            showBanner(
                text: ActivityStateContent.offlineBannerText,
                actionTitle: ActivityStateContent.offlineRetryTitle
            ) { [weak self] in
                self?.viewModel.loadMore()
            }
        } else if filters.contains(.vote), itemCount > 0, itemCount < Self.votedSparseThreshold {
            showBanner(text: ActivityStateContent.votedTitle, actionTitle: nil, action: nil)
        } else {
            hideBanner()
        }
    }

    private func showBanner(text: String, actionTitle: String?, action: (() -> Void)?) {
        bannerLabel.text = text
        bannerAction = action
        if let actionTitle, action != nil {
            bannerButton.configuration?.title = actionTitle
            bannerButton.isHidden = false
        } else {
            bannerButton.isHidden = true
        }
        bannerView.isHidden = false
    }

    private func hideBanner() {
        bannerAction = nil
        bannerView.isHidden = true
    }

    /// The full-screen empty state, chosen from the active filters (see
    /// `ActivityStateContent`). The general case's escape-hatch buttons get their
    /// actions wired here.
    private func emptyBackgroundView(filters: Set<ActivityFilterType>) -> UIView {
        var config = ActivityStateContent.emptyConfiguration(filters: filters)
        if filters.isEmpty {
            config.buttonProperties.primaryAction = UIAction { [weak self] _ in
                self?.browseCommunities()
            }
            config.secondaryButtonProperties.primaryAction = UIAction { [weak self] _ in
                self?.seeSaved()
            }
        }
        return config.makeContentView()
    }

    private func browseCommunities() {
        Haptics.tap()
        (view.window as? MainWindow)?.selectCommunitiesTab()
    }

    private func seeSaved() {
        Haptics.tap()
        // The authoritative saved feed is the server-backed `.saved` feed on the
        // Posts tab (Activity's own `.save` filter is a local best-effort view).
        (view.window as? MainWindow)?.selectSavedFeed(sort: nil)
    }

    // MARK: Grouping

    private func groupedByDay(_ items: [ActivityItem]) -> [(section: String, items: [ActivityItem])] {
        var buckets: [(label: String, date: Date, items: [ActivityItem])] = []
        var labelToIndex: [String: Int] = [:]

        for item in items {
            let label = dayLabel(for: item.occurredAt)
            if let idx = labelToIndex[label] {
                buckets[idx].items.append(item)
            } else {
                labelToIndex[label] = buckets.count
                buckets.append((label: label, date: item.occurredAt, items: [item]))
            }
        }

        return buckets.map { (section: $0.label, items: $0.items) }
    }

    private func dayLabel(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return NSLocalizedString("Today", comment: "Activity day section: today")
        }
        if Calendar.current.isDateInYesterday(date) {
            return NSLocalizedString("Yesterday", comment: "Activity day section: yesterday")
        }
        return DateFormatter.activityDaySection.string(from: date)
    }

    // MARK: Navigation / actions

    private func navigate(to item: ActivityItem) {
        switch item.object {
        case let .post(post):
            (view.window as? MainWindow)?.display(
                serverPostId: Components.Schemas.PostID(post.serverPostId),
                accountKeychainId: accountKeychainId
            )
        case let .comment(comment):
            guard let serverPostId = comment.serverPostId else { return }
            (view.window as? MainWindow)?.display(
                serverPostId: Components.Schemas.PostID(serverPostId),
                accountKeychainId: accountKeychainId,
                scrollToCommentId: Components.Schemas.CommentID(comment.serverCommentId)
            )
        }
    }

    /// Votes on the post through the per-account optimistic outbox path (the same
    /// `lemmyService.vote` the feed uses): the local write applies synchronously
    /// and flows back through the activity observation; failures are retried by
    /// the outbox.
    private func vote(serverPostId: Int64, action: VoteStatus.Action) async {
        let scope = accountService.scope(forAccountKeychainId: accountKeychainId)
        guard !scope.isSignedOut else {
            presentSignInGate(
                title: NSLocalizedString("Sign in to vote", comment: "Sign-in gate title when a signed-out user tries to vote")
            )
            return
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        do {
            try await scope.lemmyService
                .vote(serverPostId: Components.Schemas.PostID(serverPostId), vote: action)
        } catch {
            alertService.handle(error, for: .vote)
        }
    }

    /// Opens an external-link post's url, honoring the user's "Open External
    /// Links in" preference.
    private func openExternalLink(_ url: URL) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await appService.open(url: url, on: self)
        }
    }

    @objc
    private func refreshTriggered() {
        viewModel.refresh()
    }

    @objc
    private func summaryButtonTapped() {
        openSummary()
    }

    private func openSummary() {
        let summaryVC = SummaryViewController(
            accountId: accountId,
            personRowId: personRowId,
            dependencies: dependencies.own
        )
        navigationController?.pushViewController(summaryVC, animated: true)
    }
}

// MARK: - UITableViewDelegate

extension ActivityViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let itemId = dataSource.itemIdentifier(for: indexPath),
              let item = itemById[itemId] else { return }
        navigate(to: item)
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let title = dataSource.snapshot().sectionIdentifiers[section]
        let header = tableView.dequeueReusableHeaderFooterView(
            withIdentifier: Self.headerReuseIdentifier
        ) ?? UITableViewHeaderFooterView(reuseIdentifier: Self.headerReuseIdentifier)
        var content = UIListContentConfiguration.header()
        content.text = title
        header.contentConfiguration = content
        return header
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let offsetY = scrollView.contentOffset.y
        let contentHeight = scrollView.contentSize.height
        let frameHeight = scrollView.frame.height
        if contentHeight > frameHeight, offsetY > contentHeight - frameHeight - 200 {
            viewModel.loadMore()
        }
    }
}

// MARK: - UISearchResultsUpdating

extension ActivityViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        viewModel.searchQuery = searchController.searchBar.text ?? ""
        viewModel.onSearchQueryChanged()
    }
}

// MARK: - DateFormatter

private extension DateFormatter {
    static let activityDaySection: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
}
