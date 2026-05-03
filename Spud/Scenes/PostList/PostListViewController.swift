//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import CoreData
import Intents
import LemmyKit
import OSLog
import SpudDataKit
import UIKit

private let logger = Logger.app

class PostListViewController: UIViewController {
    typealias OwnDependencies =
        HasAccountService &
        HasAlertService &
        HasAppearanceService &
        HasDataStore
    typealias NestedDependencies =
        PostDetailViewController.Dependencies &
        PostListPostViewModel.Dependencies
    typealias Dependencies = NestedDependencies & OwnDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    var dataStore: DataStoreType {
        dependencies.own.dataStore
    }

    var accountService: AccountServiceType {
        dependencies.own.accountService
    }

    var alertService: AlertServiceType {
        dependencies.own.alertService
    }

    var appearanceService: AppearanceServiceType {
        dependencies.own.appearanceService
    }

    // MARK: Public

    var viewModelSubject: CurrentValueSubject<PostListViewModelType, Never>
    var viewModel: PostListViewModelType {
        viewModelSubject.value
    }

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
        /// PageElement objectID (FRC tracks LemmyPageElement, not the post itself).
        case pageElement(NSManagedObjectID)
        case loadingIndicator
    }

    private var dataSource: UITableViewDiffableDataSource<Section, Item>!

    // MARK: Private

    var disposables = Set<AnyCancellable>()

    var postsResults: NSFetchedResultsController<LemmyPageElement>?

    var isLoadingIndicatorHidden = true {
        didSet {
            guard oldValue != isLoadingIndicatorHidden, dataSource != nil else { return }
            applyLoadingIndicatorVisibility()
        }
    }

    var sortTypeBarButtonItem: UIBarButtonItem!
    var sortTypeMenuActionsBySortType: [Components.Schemas.SortType: UIAction] = [:]
    var sortTypeActiveAction: UIAction!
    var sortTypeHotAction: UIAction!
    var sortTypeNewAction: UIAction!
    var sortTypeOldAction: UIAction!
    var sortTypeTopSixHourAction: UIAction!
    var sortTypeTopTwelveHourAction: UIAction!
    var sortTypeTopDayAction: UIAction!
    var sortTypeTopWeekAction: UIAction!
    var sortTypeTopMonthAction: UIAction!
    var sortTypeTopThreeMonthAction: UIAction!
    var sortTypeTopSixMonthAction: UIAction!
    var sortTypeTopNineMonthAction: UIAction!
    var sortTypeTopYearAction: UIAction!
    var sortTypeTopAllAction: UIAction!
    var sortTypeMostCommentsAction: UIAction!
    var sortTypeNewCommentsAction: UIAction!
    var sortTypeControversialAction: UIAction!
    var sortTypeScaledAction: UIAction!

    // MARK: Functions

    init(feed: LemmyFeed, dependencies: Dependencies) {
        self.dependencies = (own: dependencies, nested: dependencies)

        let viewModel = PostListViewModel(
            feed: feed,
            dependencies: dependencies
        )
        viewModelSubject = .init(viewModel)

        super.init(nibName: nil, bundle: nil)

        setup()
        bindViewModel()
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

        func makeAction(for sortType: Components.Schemas.SortType) -> UIAction {
            let menuItem = sortType.itemForMenu
            let action = UIAction(
                title: menuItem.title,
                image: menuItem.image
            ) { [weak self] _ in
                self?.viewModel.inputs.didChangeSortType(sortType)
            }
            sortTypeMenuActionsBySortType[sortType] = action
            return action
        }

        sortTypeActiveAction = makeAction(for: .Active)
        sortTypeHotAction = makeAction(for: .Hot)
        sortTypeNewAction = makeAction(for: .New)
        sortTypeOldAction = makeAction(for: .Old)
        sortTypeTopSixHourAction = makeAction(for: .TopSixHour)
        sortTypeTopTwelveHourAction = makeAction(for: .TopTwelveHour)
        sortTypeTopDayAction = makeAction(for: .TopDay)
        sortTypeTopWeekAction = makeAction(for: .TopWeek)
        sortTypeTopMonthAction = makeAction(for: .TopMonth)
        sortTypeTopThreeMonthAction = makeAction(for: .TopThreeMonths)
        sortTypeTopSixMonthAction = makeAction(for: .TopSixMonths)
        sortTypeTopNineMonthAction = makeAction(for: .TopNineMonths)
        sortTypeTopYearAction = makeAction(for: .TopYear)
        sortTypeTopAllAction = makeAction(for: .TopAll)
        sortTypeMostCommentsAction = makeAction(for: .MostComments)
        sortTypeNewCommentsAction = makeAction(for: .NewComments)
        sortTypeControversialAction = makeAction(for: .Controversial)
        sortTypeScaledAction = makeAction(for: .Scaled)

        sortTypeBarButtonItem = UIBarButtonItem(
            title: "Sort type",
            image: UIImage(systemName: "line.horizontal.3.decrease.circle"),
            menu: nil
        )
        navigationItem.rightBarButtonItem = sortTypeBarButtonItem
    }

    private func buildSortTypeMenu() {
        let sortTypeMenu = UIMenu(
            title: "",
            options: .singleSelection,
            children: [
                UIMenu(
                    title: "",
                    options: .displayInline,
                    children: [
                        sortTypeActiveAction,
                        sortTypeHotAction,
                        sortTypeNewAction,
                        sortTypeOldAction,
                        sortTypeControversialAction,
                        sortTypeScaledAction,
                    ]
                ),
                UIMenu(
                    title: "Top",
                    options: .singleSelection,
                    children: [
                        sortTypeTopSixHourAction,
                        sortTypeTopTwelveHourAction,
                        sortTypeTopDayAction,
                        sortTypeTopWeekAction,
                        sortTypeTopMonthAction,
                        sortTypeTopThreeMonthAction,
                        sortTypeTopSixMonthAction,
                        sortTypeTopNineMonthAction,
                        sortTypeTopYearAction,
                        sortTypeTopAllAction,
                    ]
                ),
                UIMenu(
                    title: "",
                    options: .displayInline,
                    children: [
                        sortTypeMostCommentsAction,
                        sortTypeNewCommentsAction,
                    ]
                ),
            ]
        )

        sortTypeBarButtonItem.menu = sortTypeMenu
    }

    private func sortTypeActionHandler(
        for sortType: Components.Schemas.SortType
    ) -> UIActionHandler {
        { [weak self] _ in
            self?.viewModel.inputs.didChangeSortType(sortType)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func bindViewModel() {
        viewModel.outputs.selectedPost
            .ignoreNil()
            .sink { [weak self] post in
                self?.postSelected(post)
            }
            .store(in: &disposables)

        viewModel.outputs.feed
            .sink { [weak self] _ in
                self?.feedChanged()
                self?.updateSelectedSortTypeMenu()
                self?.donateIntent()
            }
            .store(in: &disposables)

        viewModel.outputs.isFetchingNextPage
            .removeDuplicates()
            .sink { [weak self] isFetchingNextPage in
                self?.isLoadingIndicatorHidden = !isFetchingNextPage
            }
            .store(in: &disposables)

        viewModel.outputs.navigationTitle
            .wrapInOptional()
            .assign(to: \.title, on: navigationItem)
            .store(in: &disposables)
    }

    private func updateSelectedSortTypeMenu() {
        for (_, value) in sortTypeMenuActionsBySortType {
            value.state = .off
        }

        let sortType = viewModel.outputs.feed.value.sortType
        guard let action = sortTypeMenuActionsBySortType[sortType] else {
            logger.assertionFailure()
            return
        }
        action.state = .on

        // it seems that setting the state on an action for an existing UIMenu doesn't
        // update the ui. The menu wasn't picking up a new state, it seems like the UIMenu
        // caches the state of the actions/menuitems.
        // Lets rebuild the whole menu.
        buildSortTypeMenu()
    }

    func feedChanged() {
        let request = LemmyPageElement.fetchRequest() as NSFetchRequest<LemmyPageElement>
        request.predicate = NSPredicate(
            format: "page.feed.id == %@",
            viewModel.outputs.feed.value.id
        )

        let pageIndex = NSSortDescriptor(keyPath: \LemmyPageElement.page.index, ascending: true)
        let postInPageIndex = NSSortDescriptor(keyPath: \LemmyPageElement.index, ascending: true)
        request.sortDescriptors = [
            pageIndex,
            postInPageIndex,
        ]

        postsResults = NSFetchedResultsController(
            fetchRequest: request,
            managedObjectContext: dataStore.mainContext,
            sectionNameKeyPath: nil, cacheName: nil
        )
        postsResults?.delegate = self

        do {
            try postsResults?.performFetch()
        } catch {
            logger.error("Failed to fetch: \(String(describing: error), privacy: .public)")
        }

        viewModel.inputs.didSelectPost(nil)
        viewModel.inputs.didChangeSelectedPostIndex(nil)

        isLoadingIndicatorHidden = numberOfPosts > 0

        tableView.reloadData()

        viewModel.inputs.didPrepareFetchController(numberOfFetchedPosts: numberOfPosts)
    }

    private func postSelected(_ post: LemmyPost) {
        guard let window = view.window as? MainWindow else {
            fatalError()
        }
        window.display(post: post)
    }

    private func vote(_ post: LemmyPost, _ action: VoteStatus.Action) async {
        // Trigger haptic feedback
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        do {
            try await accountService
                .lemmyService(for: viewModel.outputs.account)
                .vote(postId: post.objectID, vote: action)
        } catch {
            alertService.handle(error, for: .vote)
        }
    }

    private func vote(at indexPath: IndexPath, _ action: VoteStatus.Action) async {
        guard let post = post(at: indexPath) else { return }
        await vote(post, action)
    }

    private func donateIntent() {
        let intent = ViewTopPostsIntent()

        let feed = viewModel.outputs.feed.value

        guard let feedType = IntentFeedType(from: feed.feedType) else {
            return
        }

        intent.feedType = feedType
        intent.sortType = .init(from: feed.sortType)

        logger.debug("Donating intent \(intent, privacy: .public)")

        let interaction = INInteraction(intent: intent, response: nil)
        interaction.donate { error in
            if let error {
                logger.error("Failed to donate intent: \(error, privacy: .public)")
            }
        }
    }
}

// MARK: - FRC helpers

extension PostListViewController {
    var numberOfPosts: Int {
        postsResults?.sections?[0].numberOfObjects ?? 0
    }

    private func pageElement(for indexPath: IndexPath) -> LemmyPageElement? {
        guard
            case let .pageElement(objectID) = dataSource.itemIdentifier(for: indexPath),
            let element = try? dataStore.mainContext.existingObject(with: objectID) as? LemmyPageElement
        else {
            return nil
        }
        return element
    }

    func post(at indexPath: IndexPath) -> LemmyPost? {
        pageElement(for: indexPath)?.post
    }

    func postInfo(at indexPath: IndexPath) -> LemmyPostInfo? {
        post(at: indexPath)?.postInfo
    }

    private func setupDataSource() {
        let mainContext = dataStore.mainContext
        let nestedDeps = dependencies.nested
        let appearance = appearanceService

        dataSource = UITableViewDiffableDataSource<Section, Item>(
            tableView: tableView
        ) { [weak self] tableView, indexPath, item in
            switch item {
            case let .pageElement(objectID):
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: PostListPostCell.reuseIdentifier,
                    for: indexPath
                ) as! PostListPostCell

                guard
                    let element = try? mainContext.existingObject(with: objectID) as? LemmyPageElement,
                    let postInfo = element.post.postInfo
                else {
                    logger.assertionFailure("Failed to resolve PostListPostCell for \(objectID)")
                    return cell
                }

                let viewModel = PostListPostViewModel(
                    postInfo: postInfo,
                    dependencies: nestedDeps
                )
                cell.configure(with: viewModel)

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
                        // TODO: make reply action
                        image: UIImage(systemName: "arrowshape.turn.up.backward")!,
                        backgroundColor: UIColor.blue
                    ),
                    trailingSecondaryAction: .init(
                        // TODO: make save post action
                        image: UIImage(systemName: "bookmark")!,
                        backgroundColor: UIColor.green
                    )
                )

                cell.swipeActionTriggered = { [weak self] action in
                    let post = postInfo.post
                    switch action {
                    case .leadingPrimary:
                        Task { await self?.vote(post, .upvote) }
                    case .leadingSecondary:
                        Task { await self?.vote(post, .downvote) }
                    case .trailingPrimary, .trailingSecondary:
                        // TODO: will be reply and save actions
                        break
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

    private func applyLoadingIndicatorVisibility() {
        var snapshot = dataSource.snapshot()
        let hasLoadingSection = snapshot.sectionIdentifiers.contains(.loading)

        if isLoadingIndicatorHidden {
            if hasLoadingSection {
                snapshot.deleteSections([.loading])
                dataSource.apply(snapshot, animatingDifferences: true)
            }
        } else if !hasLoadingSection {
            snapshot.appendSections([.loading])
            snapshot.appendItems([.loadingIndicator], toSection: .loading)
            dataSource.apply(snapshot, animatingDifferences: true)
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
            viewModel.inputs.didScrollToBottom()
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let post = post(at: indexPath) else { return }
        viewModel.inputs.didSelectPost(post)
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
        // The user pressed on the preview -> lets open the cell
        guard let indexPath = configuration.identifier as? IndexPath,
              let post = post(at: indexPath) else { return }
        viewModel.inputs.didSelectPost(post)
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
            actionProvider: { _ in
                let upvoteAction = UIAction(
                    title: NSLocalizedString("Upvote", comment: ""),
                    image: generalAppearance.upvoteIcon
                ) { [weak self] _ in
                    Task {
                        await self?.vote(at: indexPath, .upvote)
                    }
                }

                let downvoteAction = UIAction(
                    title: NSLocalizedString("Downvote", comment: ""),
                    image: generalAppearance.downvoteIcon
                ) { [weak self] _ in
                    Task {
                        await self?.vote(at: indexPath, .downvote)
                    }
                }

                return UIMenu(title: "", children: [
                    upvoteAction,
                    downvoteAction,
                ])
            }
        )
    }
}

// MARK: - Core Data

extension PostListViewController: NSFetchedResultsControllerDelegate {
    nonisolated func controller(
        _ controller: NSFetchedResultsController<NSFetchRequestResult>,
        didChangeContentWith snapshot: NSDiffableDataSourceSnapshotReference
    ) {
        let frcSnapshot = snapshot as NSDiffableDataSourceSnapshot<Int, NSManagedObjectID>
        MainActor.assumeIsolated {
            isLoadingIndicatorHidden = true

            var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
            snapshot.appendSections([.posts])
            snapshot.appendItems(
                frcSnapshot.itemIdentifiers.map { Item.pageElement($0) },
                toSection: .posts
            )
            if !isLoadingIndicatorHidden {
                snapshot.appendSections([.loading])
                snapshot.appendItems([.loadingIndicator], toSection: .loading)
            }
            dataSource.apply(snapshot, animatingDifferences: true)
        }
    }
}
