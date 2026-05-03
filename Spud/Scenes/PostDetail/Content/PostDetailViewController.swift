//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import CoreData
import Foundation
import LemmyKit
import OSLog
import SafariServices
import SpudDataKit
import UIKit

private let logger = Logger.app

class PostDetailViewController: UIViewController {
    typealias OwnDependencies =
        HasAccountService &
        HasAlertService &
        HasAppDatabase &
        HasAppService &
        HasAppearanceService &
        HasDataStore &
        HasImageService &
        HasPostContentDetectorService &
        HasPreferencesService
    typealias NestedDependencies =
        PersonOrLoadingViewController.Dependencies
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

    var appDatabase: AppDatabase {
        dependencies.own.appDatabase
    }

    var imageService: ImageServiceType {
        dependencies.own.imageService
    }

    var postContentDetector: PostContentDetectorServiceType {
        dependencies.own.postContentDetectorService
    }

    // MARK: - Public

    var postInfo: LemmyPostInfo {
        viewModel.postInfo
    }

    func setPostInfo(_ postInfo: LemmyPostInfo) {
        observationTask?.cancel()
        commentObservationTask?.cancel()

        viewModel = PostDetailViewModel(
            postInfo: postInfo,
            dependencies: dependencies.own
        )

        startObservations()
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

    private var viewModel: PostDetailViewModel
    private var headerRow: PostDetailHeaderRow?
    private var commentRowsByElementId: [Int64: PostDetailCommentRow] = [:]
    private var observationTask: Task<Void, Never>?
    private var commentObservationTask: Task<Void, Never>?

    private var dataSource: UITableViewDiffableDataSource<Section, Item>!
    private var isFirstAppearance: Bool = true

    // MARK: Functions

    init(postInfo: LemmyPostInfo, dependencies: Dependencies) {
        self.dependencies = (own: dependencies, nested: dependencies)
        viewModel = PostDetailViewModel(postInfo: postInfo, dependencies: dependencies)

        super.init(nibName: nil, bundle: nil)

        setup()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        observationTask?.cancel()
        commentObservationTask?.cancel()
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
        startObservations()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if isFirstAppearance {
            Task { await markAsRead() }
        }
        isFirstAppearance = false
    }

    private func markAsRead() async {
        do {
            try await accountService
                .lemmyService(for: postInfo.post.account)
                .markAsRead(serverPostId: postInfo.post.postId)
        } catch {
            alertService.handle(error, for: .markAsRead)
        }
    }

    private func startObservations() {
        let keychainId = postInfo.post.account.id
        let serverPostId = Int64(postInfo.post.postId)

        guard let postRowId = appDatabase.postRowIdSync(
            forKeychainId: keychainId,
            serverPostId: serverPostId
        ) else {
            // Post not yet mirrored; trigger a comment fetch which will
            // dual-write everything we need, then the observation can
            // bring rows in on the next start.
            viewModel.didPrepareObservation(numberOfFetchedComments: 0)
            return
        }

        observationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await row in appDatabase.observePostDetailHeader(postRowId: postRowId) {
                if Task.isCancelled { break }
                headerRow = row
                applySnapshot()
            }
        }

        startCommentObservation(postRowId: postRowId)
    }

    private func startCommentObservation(postRowId: Int64) {
        commentObservationTask?.cancel()

        let sortTypeRaw = viewModel.commentSortType.rawValue
        commentObservationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var hasReceivedFirstSnapshot = false
            for await rows in appDatabase.observePostDetailComments(
                postRowId: postRowId,
                sortType: sortTypeRaw
            ) {
                if Task.isCancelled { break }
                commentRowsByElementId = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
                applySnapshot(orderedComments: rows)
                if !hasReceivedFirstSnapshot {
                    hasReceivedFirstSnapshot = true
                    viewModel.didPrepareObservation(numberOfFetchedComments: rows.count)
                }
            }
        }
    }

    private func applySnapshot(orderedComments: [PostDetailCommentRow]? = nil) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.header, .comments])
        snapshot.appendItems([.header], toSection: .header)
        snapshot.reloadItems([.header])

        let comments = orderedComments ?? Array(commentRowsByElementId.values)
            .sorted { $0.position < $1.position }
        let items = comments.map { Item.comment(elementId: $0.id) }
        snapshot.appendItems(items, toSection: .comments)
        snapshot.reloadItems(items)

        dataSource.apply(snapshot, animatingDifferences: true)
    }

    @objc
    private func reloadData() {
        Task { await reloadAsync() }
    }

    private func reloadAsync() async {
        do {
            try await accountService
                .lemmyService(for: postInfo.post.account)
                .fetchComments(
                    serverPostId: postInfo.post.postId,
                    sortType: viewModel.commentSortType
                )
        } catch {
            alertService.handle(error, for: .fetchComments)
        }
        refreshControl.endRefreshing()
    }

    @objc
    private func openInBrowser() {
        Task { await appService.openInBrowser(post: postInfo.post, on: self) }
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
            logger.assertionFailure("unimplemented")

        case .none:
            Task { await appService.open(url: url, on: self) }
        }
    }

    private func linkTappedFromPreview(_ safariVC: SFSafariViewController) {
        present(safariVC, animated: true)
    }

    private func voteOnPost(_ action: VoteStatus.Action) async {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        do {
            try await accountService
                .lemmyService(for: postInfo.post.account)
                .vote(serverPostId: postInfo.post.postId, vote: action)
        } catch {
            alertService.handle(error, for: .vote)
        }
    }

    private func voteOnComment(serverCommentId: Int64, action: VoteStatus.Action) async {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        do {
            try await accountService
                .lemmyService(for: postInfo.post.account)
                .vote(serverCommentId: Components.Schemas.CommentID(serverCommentId), vote: action)
        } catch {
            alertService.handle(error, for: .vote)
        }
    }
}

// MARK: - Data source

extension PostDetailViewController {
    enum Section: Int, Hashable {
        case header
        case comments
    }

    enum Item: Hashable {
        case header
        case comment(elementId: Int64)
    }

    private func setupDataSource() {
        let appearance = appearanceService
        let imageService = imageService
        let postContentDetector = postContentDetector
        let appService = appService

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
                if let row = self?.headerRow {
                    let viewModel = PostDetailHeaderViewModel(
                        row: row,
                        appearance: appearance,
                        postContentDetector: postContentDetector
                    )
                    cell.configure(with: viewModel, imageService: imageService)
                }
                cell.linkTapped = { [weak self] url in self?.linkTapped(url) }
                cell.linkTappedFromPreview = { [weak self] safariVC in self?.linkTappedFromPreview(safariVC) }
                cell.upvoteTapped = { [weak self] in
                    Task { await self?.voteOnPost(.upvote) }
                }
                cell.downvoteTapped = { [weak self] in
                    Task { await self?.voteOnPost(.downvote) }
                }
                cell.isBeingConfigured = false
                return cell

            case let .comment(elementId):
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: PostDetailCommentCell.reuseIdentifier,
                    for: indexPath
                ) as! PostDetailCommentCell

                guard let row = self?.commentRowsByElementId[elementId] else {
                    logger.assertionFailure("Missing PostDetailCommentRow for element \(elementId)")
                    return cell
                }

                let viewModel = PostDetailCommentViewModel(row: row, appearance: appearance)
                cell.configure(with: viewModel)
                cell.linkTapped = { [weak self] url in self?.linkTapped(url) }

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
                        image: UIImage(systemName: "bookmark")!,
                        backgroundColor: UIColor.green
                    )
                )

                cell.swipeActionTriggered = { [weak self] action in
                    guard let serverCommentId = row.serverCommentId else { return }
                    switch action {
                    case .leadingPrimary:
                        Task { await self?.voteOnComment(serverCommentId: serverCommentId, action: .upvote) }
                    case .leadingSecondary:
                        Task { await self?.voteOnComment(serverCommentId: serverCommentId, action: .downvote) }
                    case .trailingPrimary, .trailingSecondary:
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
        guard
            indexPath.section == 1,
            case let .comment(elementId) = dataSource.itemIdentifier(for: indexPath),
            let serverCommentId = commentRowsByElementId[elementId]?.serverCommentId
        else { return nil }

        let generalAppearance = appearanceService.general
        return UIContextMenuConfiguration(
            identifier: indexPath as NSCopying,
            previewProvider: nil,
            actionProvider: { _ in
                let upvoteAction = UIAction(
                    title: NSLocalizedString("Upvote", comment: ""),
                    image: generalAppearance.upvoteIcon
                ) { [weak self] _ in
                    Task { await self?.voteOnComment(serverCommentId: serverCommentId, action: .upvote) }
                }
                let downvoteAction = UIAction(
                    title: NSLocalizedString("Downvote", comment: ""),
                    image: generalAppearance.downvoteIcon
                ) { [weak self] _ in
                    Task { await self?.voteOnComment(serverCommentId: serverCommentId, action: .downvote) }
                }
                return UIMenu(title: "", children: [upvoteAction, downvoteAction])
            }
        )
    }
}
