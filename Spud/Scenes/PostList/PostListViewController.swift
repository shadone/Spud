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
import UIKit

private let logger = Logger.app

class PostListViewController: UIViewController {
    typealias OwnDependencies =
        HasAccountService &
        HasAlertService &
        HasAppDatabase &
        HasAppearanceService &
        HasImageService &
        HasPostContentDetectorService
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

    // MARK: Public

    private let viewModel: PostListViewModel

    // MARK: UI Properties

    lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.rowHeight = UITableView.automaticDimension

        tableView.delegate = self

        tableView.register(PostListPostCell.self, forCellReuseIdentifier: PostListPostCell.reuseIdentifier)
        tableView.register(LoadingFooterCell.self, forCellReuseIdentifier: LoadingFooterCell.reuseIdentifier)

        return tableView
    }()

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
    private var orderedRows: [PostListRow] = []
    /// Set once the GRDB observation has produced its first snapshot for the
    /// current feed, so the designed empty state only shows after the initial
    /// load settles (not as a flash during first fetch).
    private var hasReceivedFirstSnapshot = false
    private var observationTask: Task<Void, Never>?
    private var titleObservationTask: Task<Void, Never>?
    private var loadingObservationTask: Task<Void, Never>?

    var sortTypeBarButtonItem: UIBarButtonItem!
    var sortTypeMenuActionsBySortType: [Components.Schemas.SortType: UIAction] = [:]

    // MARK: Functions

    init(feed: FeedHandle, accountKeychainId: String, dependencies: Dependencies) {
        self.dependencies = (own: dependencies, nested: dependencies)

        viewModel = PostListViewModel(
            feed: feed,
            accountKeychainId: accountKeychainId,
            dependencies: dependencies
        )

        super.init(nibName: nil, bundle: nil)

        setup()
        navigationItem.title = viewModel.navigationTitle
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        observationTask?.cancel()
        titleObservationTask?.cancel()
        loadingObservationTask?.cancel()
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

        let viewModel = viewModel
        titleObservationTask = Task { @MainActor [weak self] in
            for await _ in Self.values(of: { viewModel.navigationTitle }) {
                if Task.isCancelled { break }
                self?.navigationItem.title = viewModel.navigationTitle
            }
        }
        loadingObservationTask = Task { @MainActor [weak self] in
            for await _ in Self.values(of: { viewModel.isFetchingNextPage }) {
                if Task.isCancelled { break }
                self?.applyLoadingIndicatorVisibility(hidden: !viewModel.isFetchingNextPage)
            }
        }
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

    private func feedChanged() {
        observationTask?.cancel()
        rowsByServerPostId.removeAll()
        orderedRows.removeAll()
        hasReceivedFirstSnapshot = false
        updateEmptyState()

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
                return
            }

            for await rows in appDatabase.observePostListRows(feedId: feedRowId) {
                if Task.isCancelled { break }
                let isFirstSnapshot = !hasReceivedFirstSnapshot
                hasReceivedFirstSnapshot = true
                apply(rows: rows)
                if isFirstSnapshot {
                    viewModel.didPrepareObservation(numberOfFetchedPosts: rows.count)
                }
            }
        }
    }

    private func apply(rows: [PostListRow]) {
        orderedRows = rows
        rowsByServerPostId = Dictionary(uniqueKeysWithValues: rows.map { ($0.serverPostId, $0) })

        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.posts])
        let items = rows.map { Item.post(serverPostId: $0.serverPostId) }
        snapshot.appendItems(items, toSection: .posts)
        snapshot.reloadItems(items)

        if viewModel.isFetchingNextPage {
            snapshot.appendSections([.loading])
            snapshot.appendItems([.loadingIndicator], toSection: .loading)
        }

        dataSource.apply(snapshot, animatingDifferences: true)

        updateEmptyState()
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

        updateEmptyState()
    }

    /// Shows a designed empty state once the feed has loaded and turned up no
    /// posts (e.g. "No saved posts yet" for the saved feed). Stays hidden
    /// during the initial fetch and whenever a page is loading.
    private func updateEmptyState() {
        let shouldShow = hasReceivedFirstSnapshot
            && orderedRows.isEmpty
            && !viewModel.isFetchingNextPage

        guard shouldShow else {
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

                let general = appearance.general
                cell.swipeActionConfiguration = .init(
                    leadingPrimaryAction: .init(
                        image: general.upvoteIcon,
                        backgroundColor: general.upvoteSwipeActionBackgroundColor
                    ),
                    leadingSecondaryAction: .init(
                        image: general.downvoteIcon,
                        backgroundColor: general.downvoteSwipeActionBackgroundColor
                    ),
                    trailingPrimaryAction: .init(
                        image: UIImage(systemName: "arrowshape.turn.up.backward")!,
                        backgroundColor: UIColor.blue
                    ),
                    trailingSecondaryAction: .init(
                        image: UIImage(systemName: row.isSaved ? "bookmark.slash" : "bookmark")!,
                        backgroundColor: UIColor.systemYellow
                    )
                )

                cell.swipeActionTriggered = { [weak self] action in
                    switch action {
                    case .leadingPrimary:
                        Task { await self?.vote(serverPostId: serverPostId, action: .upvote) }
                    case .leadingSecondary:
                        Task { await self?.vote(serverPostId: serverPostId, action: .downvote) }
                    case .trailingPrimary:
                        break
                    case .trailingSecondary:
                        self?.toggleSaved(serverPostId: serverPostId)
                    }
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
            Haptics.warning()
            presentErrorAlert(
                title: NSLocalizedString("Sign in to save", comment: "Title of the alert shown when a signed-out user tries to save a post"),
                message: NSLocalizedString(
                    "You need to be signed in to an account to save posts.",
                    comment: "Body of the alert shown when a signed-out user tries to save a post"
                )
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

    private func postSelected(serverPostId: Int64) {
        guard let window = view.window as? MainWindow else { fatalError() }
        window.display(
            serverPostId: Components.Schemas.PostID(serverPostId),
            accountKeychainId: viewModel.accountKeychainId
        )
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

    func tableView(
        _ tableView: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        let generalAppearance = appearanceService.general
        return UIContextMenuConfiguration(
            identifier: indexPath as NSCopying,
            previewProvider: nil,
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

                return UIMenu(title: "", children: [upvoteAction, downvoteAction, saveAction])
            }
        )
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
