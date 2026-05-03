//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import CoreData
import OSLog
import SafariServices
import SpudDataKit
import UIKit

private let logger = Logger.app

class PostDetailViewController: UIViewController {
    typealias OwnDependencies =
        HasAccountService &
        HasAlertService &
        HasAppService &
        HasAppearanceService &
        HasDataStore
    typealias NestedDependencies =
        PersonOrLoadingViewController.Dependencies &
        PostDetailCommentViewModel.Dependencies &
        PostDetailHeaderViewModel.Dependencies &
        PostDetailViewModel.Dependencies
    typealias Dependencies = NestedDependencies & OwnDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    var dataStore: DataStoreType {
        dependencies.own.dataStore
    }

    var appearanceService: AppearanceServiceType {
        dependencies.own.appearanceService
    }

    var appService: AppServiceType {
        dependencies.own.appService
    }

    var accountService: AccountServiceType {
        dependencies.own.accountService
    }

    var alertService: AlertServiceType {
        dependencies.own.alertService
    }

    // MARK: - Public

    var postInfo: LemmyPostInfo {
        viewModel.outputs.postInfo
    }

    func setPostInfo(_ postInfo: LemmyPostInfo) {
        disposables.removeAll()

        viewModel = PostDetailViewModel(
            postInfo: postInfo,
            dependencies: dependencies.nested
        )

        bindViewModel()
        setupFRC()

//        tableView.reloadData()
//        tableView.contentOffset = .zero

        execFRC()
    }

    // MARK: UI Properties

    lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.rowHeight = UITableView.automaticDimension

        tableView.delegate = self

        tableView.refreshControl = refreshControl

        tableView.register(PostDetailHeaderCell.self, forCellReuseIdentifier: PostDetailHeaderCell.reuseIdentifier)
        tableView.register(PostDetailCommentCell.self, forCellReuseIdentifier: PostDetailCommentCell.reuseIdentifier)

        return tableView
    }()

    lazy var refreshControl: UIRefreshControl = {
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(reloadData), for: .valueChanged)
        return refreshControl
    }()

    // MARK: - Private

    private var viewModel: PostDetailViewModelType
    private var disposables = Set<AnyCancellable>()

    private var commentsFRC: NSFetchedResultsController<LemmyCommentElement>?
    private var dataSource: UITableViewDiffableDataSource<Section, Item>!

    /// Tracks if viewWillAppear has been called before.
    private var isFirstAppearance: Bool = true

    // MARK: Functions

    init(postInfo: LemmyPostInfo, dependencies: Dependencies) {
        self.dependencies = (own: dependencies, nested: dependencies)

        viewModel = PostDetailViewModel(
            postInfo: postInfo,
            dependencies: dependencies
        )

        super.init(nibName: nil, bundle: nil)

        setup()
        setupFRC()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        view.backgroundColor = .systemBackground

        let openInBrowser = UIBarButtonItem(
            image: UIImage(systemName: "safari")!,
            style: .plain,
            target: self,
            action: #selector(openInBrowser)
        )
        navigationItem.rightBarButtonItem = openInBrowser

        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        setupDataSource()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        bindViewModel()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if isFirstAppearance {
            execFRC()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if isFirstAppearance {
            Task {
                await markAsRead()
            }
        }

        isFirstAppearance = false
    }

    private func markAsRead() async {
        do {
            try await accountService
                .lemmyService(for: postInfo.post.account)
                .markAsRead(postId: postInfo.post.objectID)
        } catch {
            alertService.handle(error, for: .markAsRead)
        }
    }

    private func setupFRC() {
        // reset the old FRC in case we are reusing the same VC for a new post.
        commentsFRC?.delegate = nil

        let postObjectId = viewModel.outputs.postInfo.post.objectID
        let sortTypeRawValue = viewModel.outputs.commentSortType.value.rawValue

        let request = LemmyCommentElement.fetchRequest() as NSFetchRequest<LemmyCommentElement>
        request.predicate = NSPredicate(
            format: "post == %@ && sortTypeRawValue == %@",
            postObjectId,
            sortTypeRawValue
        )
        request.fetchBatchSize = 100
        request.relationshipKeyPathsForPrefetching = ["comment"]
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \LemmyCommentElement.index, ascending: true),
        ]

        commentsFRC = NSFetchedResultsController(
            fetchRequest: request,
            managedObjectContext: dataStore.mainContext,
            sectionNameKeyPath: nil, cacheName: nil
        )
        commentsFRC?.delegate = self
    }

    private func execFRC() {
        do {
            try commentsFRC?.performFetch()
        } catch {
            logger.error("Failed to fetch comments: \(String(describing: error), privacy: .public)")
        }

        viewModel.inputs.didPrepareFetchController(numberOfFetchedComments: numberOfComments)
    }

    private func bindViewModel() { }

    @objc
    private func reloadData() {
        Task {
            await reloadData()
        }
    }

    private func reloadData() async {
        do {
            try await accountService
                .lemmyService(for: postInfo.post.account)
                .fetchComments(
                    postId: postInfo.post.objectID,
                    sortType: viewModel.outputs.commentSortType.value
                )
        } catch {
            alertService.handle(error, for: .fetchComments)
        }
        refreshControl.endRefreshing()
    }

    @objc
    private func openInBrowser() {
        Task {
            await appService.openInBrowser(post: postInfo.post, on: self)
        }
    }

    private func linkTapped(_ url: URL) {
        switch url.spud {
        case let .person(personId, instance):
            let vc = PersonOrLoadingViewController(
                personId: personId,
                instance: instance,
                account: postInfo.post.account,
                dependencies: dependencies.nested
            )
            navigationController?.pushViewController(vc, animated: true)

        case .post:
            // TODO: push a new post detail
            logger.assertionFailure("unimplemented")

        case .none:
            Task {
                await appService.open(url: url, on: self)
            }
        }
    }

    private func linkTappedFromPreview(_ safariVC: SFSafariViewController) {
        present(safariVC, animated: true)
    }

    private func voteOnPost(_ action: VoteStatus.Action) async {
        // Trigger haptic feedback
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        do {
            try await accountService
                .lemmyService(for: postInfo.post.account)
                .vote(postId: postInfo.post.objectID, vote: action)
        } catch {
            alertService.handle(error, for: .vote)
        }
    }

    private func vote(_ commentElement: LemmyCommentElement, _ action: VoteStatus.Action) async {
        guard let comment = commentElement.comment else {
            logger.assertionFailure("Vote on more element?")
            return
        }

        // Trigger haptic feedback
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        do {
            try await accountService
                .lemmyService(for: postInfo.post.account)
                .vote(commentId: comment.objectID, vote: action)
        } catch {
            alertService.handle(error, for: .vote)
        }
    }

    private func vote(commentAt indexPath: IndexPath, _ action: VoteStatus.Action) async {
        guard let element = commentElement(at: indexPath) else { return }
        await vote(element, action)
    }
}

// MARK: - FRC helpers

extension PostDetailViewController {
    enum Section: Int, Hashable {
        case header
        case comments
    }

    enum Item: Hashable {
        case header
        case comment(NSManagedObjectID)
    }

    var numberOfComments: Int {
        commentsFRC?.sections?[0].numberOfObjects ?? 0
    }

    func commentElement(at indexPath: IndexPath) -> LemmyCommentElement? {
        guard
            case let .comment(objectID) = dataSource.itemIdentifier(for: indexPath),
            let element = try? dataStore.mainContext.existingObject(with: objectID) as? LemmyCommentElement
        else {
            return nil
        }
        return element
    }

    private func setupDataSource() {
        let mainContext = dataStore.mainContext
        let nestedDeps = dependencies.nested
        let appearance = appearanceService
        let appService = appService
        let headerViewModel = viewModel.outputs.headerViewModel

        dataSource = UITableViewDiffableDataSource<Section, Item>(
            tableView: tableView
        ) { [weak self] tableView, indexPath, item in
            switch item {
            case .header:
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: PostDetailHeaderCell.reuseIdentifier,
                    for: indexPath
                ) as! PostDetailHeaderCell

                cell.tableView = tableView
                cell.appService = appService

                cell.isBeingConfigured = true
                cell.configure(with: headerViewModel)
                cell.linkTapped = { [weak self] url in
                    self?.linkTapped(url)
                }
                cell.linkTappedFromPreview = { [weak self] safariVC in
                    self?.linkTappedFromPreview(safariVC)
                }
                cell.upvoteTapped = { [weak self] in
                    Task { await self?.voteOnPost(.upvote) }
                }
                cell.downvoteTapped = { [weak self] in
                    Task { await self?.voteOnPost(.downvote) }
                }
                cell.isBeingConfigured = false

                return cell

            case let .comment(objectID):
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: PostDetailCommentCell.reuseIdentifier,
                    for: indexPath
                ) as! PostDetailCommentCell

                guard
                    let element = try? mainContext.existingObject(with: objectID) as? LemmyCommentElement
                else {
                    logger.assertionFailure("Failed to resolve LemmyCommentElement for \(objectID)")
                    return cell
                }

                let viewModel = PostDetailCommentViewModel(
                    comment: element,
                    dependencies: nestedDeps
                )
                cell.configure(with: viewModel)

                cell.linkTapped = { [weak self] url in
                    self?.linkTapped(url)
                }

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
                        // TODO: make save comment action
                        image: UIImage(systemName: "bookmark")!,
                        backgroundColor: UIColor.green
                    )
                )

                cell.swipeActionTriggered = { [weak self] action in
                    switch action {
                    case .leadingPrimary:
                        Task { await self?.vote(element, .upvote) }
                    case .leadingSecondary:
                        Task { await self?.vote(element, .downvote) }
                    case .trailingPrimary, .trailingSecondary:
                        // TODO: will be reply and save actions
                        break
                    }
                }

                return cell
            }
        }

        var initial = NSDiffableDataSourceSnapshot<Section, Item>()
        initial.appendSections([.header])
        initial.appendItems([.header], toSection: .header)
        dataSource.apply(initial, animatingDifferences: false)
    }
}

// MARK: - UITableView Delegate

extension PostDetailViewController: UITableViewDelegate {
    // MARK: Context Menu

    func tableView(
        _ tableView: UITableView,
        previewForHighlightingContextMenuWithConfiguration configuration: UIContextMenuConfiguration
    ) -> UITargetedPreview? {
        guard let indexPath = configuration.identifier as? IndexPath else { fatalError() }
        guard let cell = tableView.cellForRow(at: indexPath) else { return nil }
        guard let cell = cell as? PostDetailCommentCell else { fatalError() }

        let parameters = UIPreviewParameters()
        parameters.backgroundColor = .clear
        parameters.visiblePath = UIBezierPath(roundedRect: cell.bounds, cornerRadius: 12)

        return UITargetedPreview(view: cell, parameters: parameters)
    }

    func tableView(
        _ tableView: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard indexPath.section == 1 else { return nil }

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
                        await self?.vote(commentAt: indexPath, .upvote)
                    }
                }

                let downvoteAction = UIAction(
                    title: NSLocalizedString("Downvote", comment: ""),
                    image: generalAppearance.downvoteIcon
                ) { [weak self] _ in
                    Task {
                        await self?.vote(commentAt: indexPath, .downvote)
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

extension PostDetailViewController: NSFetchedResultsControllerDelegate {
    nonisolated func controller(
        _ controller: NSFetchedResultsController<NSFetchRequestResult>,
        didChangeContentWith snapshot: NSDiffableDataSourceSnapshotReference
    ) {
        let frcSnapshot = snapshot as NSDiffableDataSourceSnapshot<Int, NSManagedObjectID>
        MainActor.assumeIsolated {
            var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
            snapshot.appendSections([.header, .comments])
            snapshot.appendItems([.header], toSection: .header)
            snapshot.appendItems(
                frcSnapshot.itemIdentifiers.map { Item.comment($0) },
                toSection: .comments
            )
            dataSource.apply(snapshot, animatingDifferences: true)
        }
    }
}
