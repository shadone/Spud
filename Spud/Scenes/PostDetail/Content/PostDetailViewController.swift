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

    /// Floating control that scrolls to the next top-level (depth-1) comment so
    /// users can skim threads fast. Hidden when there is no next top-level
    /// comment below the current scroll position.
    lazy var jumpToNextButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.image = UIImage(systemName: "chevron.down")
        config.cornerStyle = .capsule
        config.baseBackgroundColor = .secondarySystemBackground
        config.baseForegroundColor = .label
        config.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityIdentifier = "jumpToNextTopComment"
        button.accessibilityLabel = NSLocalizedString(
            "Next top-level comment",
            comment: "Accessibility label for the jump-to-next-comment button"
        )
        button.addTarget(self, action: #selector(jumpToNextTopCommentTapped), for: .touchUpInside)
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.2
        button.layer.shadowRadius = 6
        button.layer.shadowOffset = CGSize(width: 0, height: 2)
        button.alpha = 0
        button.isHidden = true
        return button
    }()

    // MARK: - Private

    private var viewModel: PostDetailViewModel
    private var headerRow: PostDetailHeaderRow?
    private var commentRowsByElementId: [Int64: PostDetailCommentRow] = [:]
    /// Per-collapsed-parent hidden-descendant counts from the last visible-tree
    /// computation. Used to render the "+N" badge on collapsed cells.
    private var collapsedDescendantCounts: [Int64: Int] = [:]
    private var observationTask: Task<Void, Never>?
    private var commentObservationTask: Task<Void, Never>?

    private var dataSource: UITableViewDiffableDataSource<Section, Item>!
    private var isFirstAppearance: Bool = true
    private var saveBarButtonItem: UIBarButtonItem!
    private var shareBarButtonItem: UIBarButtonItem!

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
        shareBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.up")!,
            style: .plain,
            target: self,
            action: #selector(sharePostTapped)
        )
        saveBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "bookmark")!,
            style: .plain,
            target: self,
            action: #selector(toggleSavedOnPostTapped)
        )
        navigationItem.rightBarButtonItems = [openInBrowser, replyToPost, shareBarButtonItem, saveBarButtonItem]

        view.addSubview(tableView)
        view.addSubview(jumpToNextButton)
        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            jumpToNextButton.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor,
                constant: -16
            ),
            jumpToNextButton.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -16
            ),
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
                viewModel.updateOrderedComments(rows)
                applySnapshot()
                if !hasReceivedFirstSnapshot {
                    hasReceivedFirstSnapshot = true
                    viewModel.didPrepareObservation(numberOfFetchedComments: rows.count)
                }
            }
        }
    }

    private func applySnapshot(animated: Bool = true) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.header, .comments])
        snapshot.appendItems([.header], toSection: .header)
        snapshot.reloadItems([.header])

        // Collapse is a pure view-layer filter over the ordered tree: hide the
        // descendants of any collapsed comment and capture the per-parent
        // hidden counts for the "+N" badge.
        let visible = viewModel.visibleCommentTree()
        collapsedDescendantCounts = visible.collapsedDescendantCounts

        let items = visible.rows.map { Item.comment(elementId: $0.id) }
        snapshot.appendItems(items, toSection: .comments)
        snapshot.reloadItems(items)

        let animate = animated && !UIAccessibility.isReduceMotionEnabled
        dataSource.apply(snapshot, animatingDifferences: animate)
        updateJumpButtonVisibility()
    }

    // MARK: - Collapse

    /// Toggles collapse for the comment element `elementId`, re-applies the
    /// filtered snapshot with animation, and fires a light haptic.
    private func toggleCollapse(elementId: Int64) {
        viewModel.toggleCollapse(elementId: elementId)
        Haptics.tap()
        applySnapshot(animated: true)
    }

    // MARK: - Jump to next top-level comment

    /// The index path of the next visible depth-1 comment whose top is below the
    /// current content offset (plus the top inset). Returns nil if none.
    private func indexPathOfNextTopLevelComment() -> IndexPath? {
        let snapshot = dataSource.snapshot()
        guard snapshot.indexOfSection(.comments) != nil else { return nil }

        // The first row whose origin sits below the current visible top edge.
        let threshold = tableView.contentOffset.y + tableView.adjustedContentInset.top + 1

        let items = snapshot.itemIdentifiers(inSection: .comments)
        for (offset, item) in items.enumerated() {
            guard case let .comment(elementId) = item else { continue }
            guard commentRowsByElementId[elementId]?.depth == 1 else { continue }

            let indexPath = IndexPath(row: offset, section: Section.comments.rawValue)
            let rect = tableView.rectForRow(at: indexPath)
            if rect.minY > threshold {
                return indexPath
            }
        }
        return nil
    }

    @objc
    private func jumpToNextTopCommentTapped() {
        guard let indexPath = indexPathOfNextTopLevelComment() else { return }
        Haptics.tap()
        tableView.scrollToRow(at: indexPath, at: .top, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    /// Shows the jump button only when there is a next top-level comment to jump
    /// to. Animated unless reduce-motion is on.
    private func updateJumpButtonVisibility() {
        let shouldShow = indexPathOfNextTopLevelComment() != nil
        guard shouldShow != (jumpToNextButton.alpha > 0) else { return }

        if shouldShow {
            jumpToNextButton.isHidden = false
        }
        let animate = !UIAccessibility.isReduceMotionEnabled
        let work = { self.jumpToNextButton.alpha = shouldShow ? 1 : 0 }
        let completion = { (_: Bool) in
            if !shouldShow { self.jumpToNextButton.isHidden = true }
        }
        if animate {
            UIView.animate(withDuration: 0.2, animations: work, completion: completion)
        } else {
            work()
            completion(true)
        }
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

    @objc
    private func sharePostTapped() {
        sharePost()
    }

    /// Shares the current post's canonical URL. Prefers the post's `ap_id`
    /// permalink; falls back to constructing it from the account instance.
    private func sharePost() {
        let instanceActorId = appDatabase.accountInstanceActorIdSync(
            forKeychainId: viewModel.accountKeychainId
        )
        guard let url = ShareURL.forPost(
            originalPostUrl: headerRow?.originalPostUrl,
            serverPostId: Int64(viewModel.serverPostId),
            instanceActorId: instanceActorId
        ) else {
            Haptics.warning()
            return
        }
        presentShareSheet(for: url, sourceItem: shareBarButtonItem)
    }

    /// Shares the comment identified by `serverCommentId`. Prefers the
    /// comment's `ap_id` permalink; falls back to `<instance>/comment/<id>`.
    private func shareComment(serverCommentId: Int64) {
        let row = commentRowsByElementId.values
            .first { $0.serverCommentId == serverCommentId }
        let instanceActorId = appDatabase.accountInstanceActorIdSync(
            forKeychainId: viewModel.accountKeychainId
        )
        guard let url = ShareURL.forComment(
            originalCommentUrl: row?.originalCommentUrl,
            serverCommentId: serverCommentId,
            instanceActorId: instanceActorId
        ) else {
            Haptics.warning()
            return
        }
        presentShareSheet(for: url)
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
            // If the tapped markdown link points to an image, open it in the
            // full-screen viewer rather than handing off to Safari.
            let contentType = postContentDetector.contentTypeForUrl(
                url: url,
                thumbnailUrl: nil,
                embedTitle: nil,
                embedDescription: nil
            )
            if case let .image(image) = contentType {
                presentMediaViewer(
                    imageUrl: image.imageUrl,
                    thumbnailUrl: image.thumbnailUrl,
                    preloadedImage: nil
                )
            } else {
                Task { await appService.open(url: url, on: self) }
            }
        }
    }

    private func linkTappedFromPreview(_ safariVC: SFSafariViewController) {
        present(safariVC, animated: true)
    }

    private func presentMediaViewer(
        imageUrl: URL,
        thumbnailUrl: URL?,
        preloadedImage: UIImage?
    ) {
        let item = MediaItem(
            imageUrl: imageUrl,
            thumbnailUrl: thumbnailUrl,
            preloadedImage: preloadedImage
        )
        let viewer = MediaViewerViewController.make(
            items: [item],
            dependencies: dependencies.own
        )
        present(viewer, animated: true)
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
                cell.imageTapped = { [weak self] imageUrl, thumbnailUrl, currentImage in
                    self?.presentMediaViewer(
                        imageUrl: imageUrl,
                        thumbnailUrl: thumbnailUrl,
                        preloadedImage: currentImage
                    )
                }
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

                let isCollapsed = self?.viewModel.isCollapsed(elementId: elementId) ?? false
                let collapsedCount = self?.collapsedDescendantCounts[elementId]
                let viewModel = PostDetailCommentViewModel(
                    row: row,
                    appearance: appearance,
                    isCollapsed: isCollapsed,
                    collapsedDescendantCount: collapsedCount
                )
                cell.configure(with: viewModel)
                cell.linkTapped = { [weak self] url in self?.linkTapped(url) }
                // Tap-to-collapse is the primary collapse affordance (Apollo
                // parity); "load more" placeholders are not collapsible.
                cell.collapseTapped = { [weak self] in
                    self?.toggleCollapse(elementId: elementId)
                }

                let general = appearance.general
                // Swipe slots stay vote / vote / reply / collapse. Collapse is
                // also available via tap; the deep trailing swipe mirrors it for
                // gesture-first users. Save moves to the context menu + nav bar.
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
                        image: UIImage(
                            systemName: isCollapsed
                                ? "arrow.up.left.and.arrow.down.right"
                                : "arrow.down.right.and.arrow.up.left"
                        )!,
                        backgroundColor: UIColor.systemIndigo
                    )
                )

                cell.swipeActionTriggered = { [weak self] action in
                    switch action {
                    case .leadingPrimary:
                        guard let serverCommentId = row.serverCommentId else { return }
                        Task { await self?.voteOnComment(serverCommentId: serverCommentId, action: .upvote) }
                    case .leadingSecondary:
                        guard let serverCommentId = row.serverCommentId else { return }
                        Task { await self?.voteOnComment(serverCommentId: serverCommentId, action: .downvote) }
                    case .trailingPrimary:
                        guard let serverCommentId = row.serverCommentId else { return }
                        self?.replyToComment(serverCommentId: serverCommentId)
                    case .trailingSecondary:
                        self?.toggleCollapse(elementId: elementId)
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
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateJumpButtonVisibility()
    }

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
                let shareAction = UIAction(
                    title: NSLocalizedString("Share", comment: "Context-menu action to share a comment"),
                    image: UIImage(systemName: "square.and.arrow.up")
                ) { [weak self] _ in
                    self?.shareComment(serverCommentId: serverCommentId)
                }
                return UIMenu(title: "", children: [upvoteAction, downvoteAction, replyAction, saveAction, shareAction])
            }
        )
    }
}
