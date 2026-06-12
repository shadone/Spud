//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import OSLog
import SafariServices
import SpudDataKit
import SpudUIKit
import UIKit

private let logger = Logger.app

class PostDetailViewController: UIViewController {
    typealias OwnDependencies =
        HasAccountService &
        HasAlertService &
        HasAppDatabase &
        HasAppService &
        HasAppearanceService &
        HasImageService &
        HasPostContentDetectorService &
        HasPreferencesService
    typealias NestedDependencies =
        PersonOrLoadingViewController.Dependencies &
        CommunityOrLoadingViewController.Dependencies
    typealias Dependencies = NestedDependencies & OwnDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

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

    var serverPostId: Components.Schemas.PostID {
        viewModel.serverPostId
    }

    func setPost(serverPostId: Components.Schemas.PostID, accountKeychainId: String) {
        observationTask?.cancel()
        commentObservationTask?.cancel()

        viewModel = PostDetailViewModel(
            serverPostId: serverPostId,
            accountKeychainId: accountKeychainId,
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
    private var saveBarButtonItem: UIBarButtonItem!

    // MARK: Functions

    init(
        serverPostId: Components.Schemas.PostID,
        accountKeychainId: String,
        dependencies: Dependencies
    ) {
        self.dependencies = (own: dependencies, nested: dependencies)
        viewModel = PostDetailViewModel(
            serverPostId: serverPostId,
            accountKeychainId: accountKeychainId,
            dependencies: dependencies
        )

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
        let replyToPost = UIBarButtonItem(
            image: UIImage(systemName: "arrowshape.turn.up.backward")!,
            style: .plain,
            target: self,
            action: #selector(replyToPostTapped)
        )
        saveBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "bookmark")!,
            style: .plain,
            target: self,
            action: #selector(toggleSavedOnPostTapped)
        )
        navigationItem.rightBarButtonItems = [openInBrowser, replyToPost, saveBarButtonItem]

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
                .lemmyService(forAccountKeychainId: viewModel.accountKeychainId)
                .markAsRead(serverPostId: viewModel.serverPostId)
        } catch {
            alertService.handle(error, for: .markAsRead)
        }
    }

    private func startObservations() {
        let keychainId = viewModel.accountKeychainId
        let serverPostId = Int64(viewModel.serverPostId)

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
                updateSaveBarButton()
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
                .lemmyService(forAccountKeychainId: viewModel.accountKeychainId)
                .fetchComments(
                    serverPostId: viewModel.serverPostId,
                    sortType: viewModel.commentSortType
                )
        } catch {
            alertService.handle(error, for: .fetchComments)
        }
        refreshControl.endRefreshing()
    }

    @objc
    private func openInBrowser() {
        Task {
            await appService.openInBrowser(
                serverPostId: viewModel.serverPostId,
                accountKeychainId: viewModel.accountKeychainId,
                on: self
            )
        }
    }

    @objc
    private func replyToPostTapped() {
        replyToPost()
    }

    private func linkTapped(_ url: URL) {
        switch url.spud {
        case let .person(personId, instance):
            let vc = PersonOrLoadingViewController(
                personId: personId,
                instance: instance,
                accountKeychainId: viewModel.accountKeychainId,
                dependencies: dependencies.nested
            )
            navigationController?.pushViewController(vc, animated: true)

        case let .community(name, instance):
            let vc = CommunityOrLoadingViewController(
                communityName: name,
                instance: instance,
                accountKeychainId: viewModel.accountKeychainId,
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
                .lemmyService(forAccountKeychainId: viewModel.accountKeychainId)
                .vote(serverPostId: viewModel.serverPostId, vote: action)
        } catch {
            alertService.handle(error, for: .vote)
        }
    }

    private func voteOnComment(serverCommentId: Int64, action: VoteStatus.Action) async {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        do {
            try await accountService
                .lemmyService(forAccountKeychainId: viewModel.accountKeychainId)
                .vote(serverCommentId: Components.Schemas.CommentID(serverCommentId), vote: action)
        } catch {
            alertService.handle(error, for: .vote)
        }
    }

    @objc
    private func toggleSavedOnPostTapped() {
        toggleSavedOnPost()
    }

    private func updateSaveBarButton() {
        let isSaved = headerRow?.isSaved ?? false
        saveBarButtonItem.image = UIImage(systemName: isSaved ? "bookmark.fill" : "bookmark")
    }

    /// Whether the backing account can perform save actions. Signed-out
    /// accounts get a "Sign in to save" alert and a warning haptic.
    private func canSaveOrPresentSignInAlert() -> Bool {
        guard !accountService.isSignedOut(forAccountKeychainId: viewModel.accountKeychainId) else {
            Haptics.warning()
            presentErrorAlert(
                title: NSLocalizedString("Sign in to save", comment: "Title of the alert shown when a signed-out user tries to save"),
                message: NSLocalizedString(
                    "You need to be signed in to an account to save posts and comments.",
                    comment: "Body of the alert shown when a signed-out user tries to save"
                )
            )
            return false
        }
        return true
    }

    private func toggleSavedOnPost() {
        guard canSaveOrPresentSignInAlert() else { return }
        let currentlySaved = headerRow?.isSaved ?? false
        Task { await setSavedOnPost(saved: !currentlySaved) }
    }

    private func setSavedOnPost(saved: Bool) async {
        Haptics.tap()
        do {
            try await accountService
                .lemmyService(forAccountKeychainId: viewModel.accountKeychainId)
                .setSaved(serverPostId: viewModel.serverPostId, saved: saved)
        } catch {
            alertService.handle(error, for: .save)
        }
    }

    private func toggleSavedOnComment(serverCommentId: Int64) {
        guard canSaveOrPresentSignInAlert() else { return }
        let row = commentRowsByElementId.values
            .first { $0.serverCommentId == serverCommentId }
        let currentlySaved = (row?.isSaved ?? false) == true
        Task { await setSavedOnComment(serverCommentId: serverCommentId, saved: !currentlySaved) }
    }

    private func setSavedOnComment(serverCommentId: Int64, saved: Bool) async {
        Haptics.tap()
        do {
            try await accountService
                .lemmyService(forAccountKeychainId: viewModel.accountKeychainId)
                .setSaved(serverCommentId: Components.Schemas.CommentID(serverCommentId), saved: saved)
        } catch {
            alertService.handle(error, for: .save)
        }
    }

    /// Reply to the post itself (a top-level comment).
    private func replyToPost() {
        presentComposer(target: .postReply(serverPostId: viewModel.serverPostId))
    }

    /// Reply to the comment identified by `serverCommentId`.
    private func replyToComment(serverCommentId: Int64) {
        presentComposer(target: .commentReply(
            serverPostId: viewModel.serverPostId,
            parentCommentId: Components.Schemas.CommentID(serverCommentId)
        ))
    }

    /// Presents the composer sheet for `target`, gating on sign-in: a
    /// signed-out account gets a "sign in to comment" alert instead.
    private func presentComposer(target: ComposerTarget) {
        let keychainId = viewModel.accountKeychainId
        guard !accountService.isSignedOut(forAccountKeychainId: keychainId) else {
            presentErrorAlert(
                title: NSLocalizedString("Sign in to comment", comment: "Title of the alert shown when a signed-out user tries to comment"),
                message: NSLocalizedString(
                    "You need to be signed in to an account to post comments.",
                    comment: "Body of the alert shown when a signed-out user tries to comment"
                )
            )
            return
        }

        let composer = ComposerViewController.makeSheet(
            target: target,
            accountKeychainId: keychainId,
            dependencies: dependencies.own
        )
        present(composer, animated: true)
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
                cell.saveTapped = { [weak self] in
                    self?.toggleSavedOnPost()
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
                        image: UIImage(systemName: (row.isSaved ?? false) ? "bookmark.slash" : "bookmark")!,
                        backgroundColor: UIColor.systemYellow
                    )
                )

                cell.swipeActionTriggered = { [weak self] action in
                    guard let serverCommentId = row.serverCommentId else { return }
                    switch action {
                    case .leadingPrimary:
                        Task { await self?.voteOnComment(serverCommentId: serverCommentId, action: .upvote) }
                    case .leadingSecondary:
                        Task { await self?.voteOnComment(serverCommentId: serverCommentId, action: .downvote) }
                    case .trailingPrimary:
                        self?.replyToComment(serverCommentId: serverCommentId)
                    case .trailingSecondary:
                        self?.toggleSavedOnComment(serverCommentId: serverCommentId)
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
            let commentRow = commentRowsByElementId[elementId],
            let serverCommentId = commentRow.serverCommentId
        else { return nil }

        let isSaved = commentRow.isSaved ?? false
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
                let replyAction = UIAction(
                    title: NSLocalizedString("Reply", comment: ""),
                    image: UIImage(systemName: "arrowshape.turn.up.backward")
                ) { [weak self] _ in
                    self?.replyToComment(serverCommentId: serverCommentId)
                }
                let saveAction = UIAction(
                    title: isSaved
                        ? NSLocalizedString("Unsave", comment: "Context-menu action to unsave a comment")
                        : NSLocalizedString("Save", comment: "Context-menu action to save a comment"),
                    image: UIImage(systemName: isSaved ? "bookmark.slash" : "bookmark")
                ) { [weak self] _ in
                    self?.toggleSavedOnComment(serverCommentId: serverCommentId)
                }
                return UIMenu(title: "", children: [upvoteAction, downvoteAction, replyAction, saveAction])
            }
        )
    }
}
