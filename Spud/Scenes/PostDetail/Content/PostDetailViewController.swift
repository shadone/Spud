//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Down
import Foundation
import LemmyKit
import OSLog
import SafariServices
import SpudDataKit
import SpudUIKit
import SpudUtilKit
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

    var preferencesService: PreferencesServiceType {
        dependencies.own.preferencesService
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
    /// The backing account's moderation capability, refreshed from the server
    /// on appearance. Drives whether mod actions show in the context menus.
    /// `.none` until the first fetch (and for signed-out accounts).
    private var moderationCapability: ModerationCapability = .none
    /// Per-collapsed-parent hidden-descendant counts from the last visible-tree
    /// computation. Used to render the "+N" badge on collapsed cells.
    private var collapsedDescendantCounts: [Int64: Int] = [:]
    private var observationTask: Task<Void, Never>?
    private var commentObservationTask: Task<Void, Never>?
    private var swipeActionsObservationTask: Task<Void, Never>?

    /// The active comment swipe-action config, sanitized for comments. Seeded
    /// from the preference and kept live via `swipeActionsObservationTask`;
    /// changes reconfigure visible comment cells.
    private var commentSwipeActionConfig: SwipeActionConfig = .defaultComments

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

        commentSwipeActionConfig = dependencies.preferencesService
            .commentSwipeActions
            .sanitized(for: .comment)

        setup()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        observationTask?.cancel()
        commentObservationTask?.cancel()
        swipeActionsObservationTask?.cancel()
    }

    private func setup() {
        view.backgroundColor = Theme.background

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
        startSwipeActionsObservation()
        startObservations()
    }

    /// Observes the comment swipe-action preference and reconfigures visible
    /// comment cells when it changes. Independent of the backing post/account,
    /// so it is started once in `viewDidLoad` rather than per `setPost`.
    private func startSwipeActionsObservation() {
        swipeActionsObservationTask?.cancel()
        swipeActionsObservationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await config in preferencesService.commentSwipeActionsStream {
                if Task.isCancelled { break }
                let sanitized = config.sanitized(for: .comment)
                guard sanitized != commentSwipeActionConfig else { continue }
                commentSwipeActionConfig = sanitized
                reconfigureVisibleSwipeActions()
            }
        }
    }

    /// Reconfigures visible comment cells so they rebuild their swipe
    /// configuration from the updated `commentSwipeActionConfig`.
    private func reconfigureVisibleSwipeActions() {
        guard dataSource != nil else { return }
        var snapshot = dataSource.snapshot()
        let commentItems = snapshot.itemIdentifiers(inSection: .comments)
        guard !commentItems.isEmpty else { return }
        snapshot.reconfigureItems(commentItems)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if isFirstAppearance, preferencesService.markPostsRead {
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

    /// Refreshes the backing account's moderation capability from the server.
    /// Best-effort: a failure (or signed-out account) leaves the capability at
    /// `.none`, simply hiding mod actions.
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

    private func startObservations() {
        refreshModerationCapability()

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

                // Parse and cache every comment body off the main thread before
                // the cells are configured, so cell dequeue is a cache hit
                // instead of a synchronous cmark parse on the scroll path.
                await Self.prewarmCommentBodies(
                    rows,
                    textSizeAdjustment: appearanceService.postDetail.textSizeAdjustment
                )
                if Task.isCancelled { break }

                applySnapshot()
                if !hasReceivedFirstSnapshot {
                    hasReceivedFirstSnapshot = true
                    viewModel.didPrepareObservation(numberOfFetchedComments: rows.count)
                }
            }
        }
    }

    /// Rebuilds and applies the header + comments snapshot. Defaults to
    /// non-animated: observation-driven updates (the header's content arriving,
    /// comments loading, votes) must land in place — animating the header row as
    /// its content fills in makes it visibly grow from zero height when the post
    /// opens. Only user-initiated structural changes (the collapse toggle) pass
    /// `animated: true`, where sliding descendants in/out is the wanted affordance.
    private func applySnapshot(animated: Bool = false) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.header, .comments])
        snapshot.appendItems([.header], toSection: .header)
        // Refresh content in place. Reconfigure (not reload) re-runs the cell
        // provider on the existing cells, avoiding the cross-dissolve that
        // reloadItems animates under `animatingDifferences: true` — that fade,
        // applied to the header and every visible comment at once, flashed the
        // whole screen on each vote and each collapse toggle. Matches
        // reconfigureVisibleSwipeActions() and PostListViewController.apply().
        snapshot.reconfigureItems([.header])

        // Collapse is a pure view-layer filter over the ordered tree: hide the
        // descendants of any collapsed comment and capture the per-parent
        // hidden counts for the "+N" badge.
        let visible = viewModel.visibleCommentTree()
        collapsedDescendantCounts = visible.collapsedDescendantCounts

        let items = visible.rows.map { Item.comment(elementId: $0.id) }
        snapshot.appendItems(items, toSection: .comments)
        snapshot.reconfigureItems(items)

        let animate = animated && !UIAccessibility.isReduceMotionEnabled
        dataSource.apply(snapshot, animatingDifferences: animate)
        updateJumpButtonVisibility()
    }

    /// Renders and caches every comment body into `MarkdownRenderer` off the main
    /// thread. Declared `nonisolated async` so its body runs on the cooperative
    /// pool (Swift 6 language mode) rather than the main actor; it captures only
    /// `Sendable` values (the rows and the text-size adjustment). Cell dequeue
    /// then hits the warm cache instead of parsing cmark on the scroll path.
    private nonisolated static func prewarmCommentBodies(
        _ rows: [PostDetailCommentRow],
        textSizeAdjustment: CGFloat
    ) async {
        for row in rows {
            if Task.isCancelled { return }
            guard let body = row.body, !body.isEmpty else { continue }
            MarkdownRenderer.shared.attributedString(
                markdown: body,
                key: MarkdownRenderer.postBodyKey(
                    markdown: body,
                    textSizeAdjustment: textSizeAdjustment
                ),
                makeStyler: {
                    DownStyler(configuration: PostDetailAppearance.bodyStylerConfiguration(
                        for: textSizeAdjustment
                    ))
                }
            )
        }
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
            switch contentType {
            case let .image(image):
                presentMediaViewer(
                    imageUrl: image.imageUrl,
                    thumbnailUrl: image.thumbnailUrl,
                    preloadedImage: nil
                )
            case let .video(video):
                presentVideoPlayer(url: video.videoUrl)
            case .externalLink, .textOrEmpty:
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

    /// The current toggle state a comment row exposes to the swipe presentation
    /// layer (save/collapse/vote glyphs reflect it).
    private static func swipeState(
        for row: PostDetailCommentRow,
        isCollapsed: Bool
    ) -> SwipeActionState {
        SwipeActionState(
            isSaved: row.isSaved ?? false,
            isUpvoted: row.voteStatus == 1,
            isDownvoted: row.voteStatus == 0,
            isCollapsed: isCollapsed
        )
    }

    /// Dispatches a configured swipe action for a comment to its existing
    /// handler. Vote / reply / save / share need a server comment id (a
    /// "load more" placeholder has none); `.collapse` works on the element id.
    private func performCommentSwipeAction(
        _ action: SwipeAction,
        elementId: Int64,
        serverCommentId: Int64?
    ) {
        switch action {
        case .none:
            break
        case .collapse:
            toggleCollapse(elementId: elementId)
        case .upvote:
            guard let serverCommentId else { return }
            Task { await voteOnComment(serverCommentId: serverCommentId, action: .upvote) }
        case .downvote:
            guard let serverCommentId else { return }
            Task { await voteOnComment(serverCommentId: serverCommentId, action: .downvote) }
        case .save:
            guard let serverCommentId else { return }
            toggleSavedOnComment(serverCommentId: serverCommentId)
        case .reply:
            guard let serverCommentId else { return }
            replyToComment(serverCommentId: serverCommentId)
        case .share:
            guard let serverCommentId else { return }
            shareComment(serverCommentId: serverCommentId)
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
            presentSignInGate(
                title: NSLocalizedString("Sign in to save", comment: "Sign-in gate title when a signed-out user tries to save")
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

    // MARK: - Report

    /// True when `creatorPersonId` matches the backing account's own person id.
    /// Reporting your own content is meaningless, so the "Report" action is
    /// hidden for it.
    private func isOwnContent(creatorPersonId: Int64?) -> Bool {
        guard let creatorPersonId else { return false }
        guard let own = appDatabase.accountOwnPersonIdsSync(
            forKeychainId: viewModel.accountKeychainId
        ) else { return false }
        return creatorPersonId == own.serverPersonId
    }

    /// Whether the backing account can report content. Signed-out accounts get
    /// a "Sign in to report" alert and a warning haptic.
    private func canReportOrPresentSignInAlert() -> Bool {
        guard !accountService.isSignedOut(forAccountKeychainId: viewModel.accountKeychainId) else {
            presentSignInGate(
                title: NSLocalizedString("Sign in to report", comment: "Sign-in gate title when a signed-out user tries to report")
            )
            return false
        }
        return true
    }

    private func reportPost() {
        guard canReportOrPresentSignInAlert() else { return }
        presentReportReasonAlert(
            title: NSLocalizedString("Report post", comment: "Report post dialog title"),
            message: NSLocalizedString("Tell the moderators why you're reporting this post.", comment: "Report post dialog message")
        ) { [weak self] reason in
            Task { await self?.submitPostReport(reason: reason) }
        }
    }

    private func submitPostReport(reason: String) async {
        Haptics.tap()
        do {
            try await accountService
                .lemmyService(forAccountKeychainId: viewModel.accountKeychainId)
                .reportPost(serverPostId: viewModel.serverPostId, reason: reason)
            Haptics.success()
            presentReportSubmittedConfirmation()
        } catch {
            alertService.handle(error, for: .reportPost)
        }
    }

    private func reportComment(serverCommentId: Int64) {
        guard canReportOrPresentSignInAlert() else { return }
        presentReportReasonAlert(
            title: NSLocalizedString("Report comment", comment: "Report comment dialog title"),
            message: NSLocalizedString("Tell the moderators why you're reporting this comment.", comment: "Report comment dialog message")
        ) { [weak self] reason in
            Task { await self?.submitCommentReport(serverCommentId: serverCommentId, reason: reason) }
        }
    }

    private func submitCommentReport(serverCommentId: Int64, reason: String) async {
        Haptics.tap()
        do {
            try await accountService
                .lemmyService(forAccountKeychainId: viewModel.accountKeychainId)
                .reportComment(serverCommentId: Components.Schemas.CommentID(serverCommentId), reason: reason)
            Haptics.success()
            presentReportSubmittedConfirmation()
        } catch {
            alertService.handle(error, for: .reportComment)
        }
    }

    // MARK: - Moderation

    /// The moderation menu for the post, or nil when the account cannot
    /// moderate the post's community. Offers Remove/Restore, Lock/Unlock,
    /// Feature (pin) to community, and (admins only) Feature to instance.
    private func postModerationMenu() -> UIMenu? {
        guard let headerRow else { return nil }
        let communityId = Components.Schemas.CommunityID(headerRow.serverCommunityId)
        guard moderationCapability.canModerate(communityId: communityId) else { return nil }

        let serverPostId = viewModel.serverPostId
        var children: [UIMenuElement] = []

        if headerRow.isRemoved {
            children.append(UIAction(
                title: NSLocalizedString("Restore", comment: "Mod action: restore a removed post"),
                image: UIImage(systemName: "arrow.uturn.backward")
            ) { [weak self] _ in
                self?.performRemovePost(serverPostId: serverPostId, removed: false)
            })
        } else {
            children.append(UIAction(
                title: NSLocalizedString("Remove", comment: "Mod action: remove a post"),
                image: UIImage(systemName: "trash.slash"),
                attributes: .destructive
            ) { [weak self] _ in
                self?.promptRemovePost(serverPostId: serverPostId)
            })
        }

        let locked = headerRow.isLocked
        children.append(UIAction(
            title: locked
                ? NSLocalizedString("Unlock", comment: "Mod action: unlock a post")
                : NSLocalizedString("Lock", comment: "Mod action: lock a post"),
            image: UIImage(systemName: locked ? "lock.open" : "lock")
        ) { [weak self] _ in
            self?.performLockPost(serverPostId: serverPostId, locked: !locked)
        })

        let featuredCommunity = headerRow.isFeaturedCommunity
        children.append(UIAction(
            title: featuredCommunity
                ? NSLocalizedString("Unpin from community", comment: "Mod action: unfeature post in community")
                : NSLocalizedString("Pin to community", comment: "Mod action: feature post in community"),
            image: UIImage(systemName: featuredCommunity ? "pin.slash" : "pin")
        ) { [weak self] _ in
            self?.performFeaturePost(serverPostId: serverPostId, featured: !featuredCommunity, local: false)
        })

        // Featuring to the instance front page is admin-only.
        if moderationCapability.isAdmin {
            let featuredLocal = headerRow.isFeaturedLocal
            children.append(UIAction(
                title: featuredLocal
                    ? NSLocalizedString("Unpin from instance", comment: "Admin action: unfeature post on instance")
                    : NSLocalizedString("Pin to instance", comment: "Admin action: feature post on instance"),
                image: UIImage(systemName: featuredLocal ? "pin.slash.fill" : "pin.fill")
            ) { [weak self] _ in
                self?.performFeaturePost(serverPostId: serverPostId, featured: !featuredLocal, local: true)
            })
        }

        return UIMenu(
            title: NSLocalizedString("Moderation", comment: "Moderation submenu title"),
            image: UIImage(systemName: "shield"),
            children: children
        )
    }

    /// The moderation menu for a comment, or nil when the account cannot
    /// moderate the post's community. Offers Remove/Restore and
    /// Distinguish/Undistinguish. The ban-from-community action is appended
    /// separately so it can be hidden for the account's own content.
    private func commentModerationMenu(
        serverCommentId: Int64,
        commentRow: PostDetailCommentRow
    ) -> UIMenu? {
        guard let headerRow else { return nil }
        let communityId = Components.Schemas.CommunityID(headerRow.serverCommunityId)
        guard moderationCapability.canModerate(communityId: communityId) else { return nil }

        var children: [UIMenuElement] = []

        if commentRow.isRemoved == true {
            children.append(UIAction(
                title: NSLocalizedString("Restore", comment: "Mod action: restore a removed comment"),
                image: UIImage(systemName: "arrow.uturn.backward")
            ) { [weak self] _ in
                self?.performRemoveComment(serverCommentId: serverCommentId, removed: false)
            })
        } else {
            children.append(UIAction(
                title: NSLocalizedString("Remove", comment: "Mod action: remove a comment"),
                image: UIImage(systemName: "trash.slash"),
                attributes: .destructive
            ) { [weak self] _ in
                self?.promptRemoveComment(serverCommentId: serverCommentId)
            })
        }

        let distinguished = commentRow.isDistinguished == true
        children.append(UIAction(
            title: distinguished
                ? NSLocalizedString("Undistinguish", comment: "Mod action: undistinguish a comment")
                : NSLocalizedString("Distinguish", comment: "Mod action: distinguish a comment"),
            image: UIImage(systemName: distinguished ? "shield.slash" : "shield")
        ) { [weak self] _ in
            self?.performDistinguishComment(serverCommentId: serverCommentId, distinguished: !distinguished)
        })

        // Ban the comment author from the community (not for your own content).
        if !isOwnContent(creatorPersonId: commentRow.creatorPersonId),
           let creatorPersonId = commentRow.creatorPersonId
        {
            children.append(UIAction(
                title: NSLocalizedString("Ban from community", comment: "Mod action: ban user from community"),
                image: UIImage(systemName: "hand.raised"),
                attributes: .destructive
            ) { [weak self] _ in
                self?.promptBanFromCommunity(
                    serverPersonId: creatorPersonId,
                    userName: commentRow.creatorName
                )
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

    private func promptRemoveComment(serverCommentId: Int64) {
        presentModerationReasonAlert(
            title: NSLocalizedString("Remove comment", comment: "Remove comment dialog title"),
            message: NSLocalizedString("Optionally tell the author why the comment was removed.", comment: "Remove comment dialog message"),
            submitTitle: NSLocalizedString("Remove", comment: "Remove alert submit button")
        ) { [weak self] reason in
            self?.performRemoveComment(serverCommentId: serverCommentId, removed: true, reason: reason)
        }
    }

    private func performRemoveComment(
        serverCommentId: Int64,
        removed: Bool,
        reason: String? = nil
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            Haptics.tap()
            do {
                try await accountService
                    .lemmyService(forAccountKeychainId: viewModel.accountKeychainId)
                    .removeComment(serverCommentId: Components.Schemas.CommentID(serverCommentId), removed: removed, reason: reason)
                Haptics.success()
            } catch {
                alertService.handle(error, for: .removeComment)
            }
        }
    }

    private func performDistinguishComment(serverCommentId: Int64, distinguished: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            Haptics.tap()
            do {
                try await accountService
                    .lemmyService(forAccountKeychainId: viewModel.accountKeychainId)
                    .distinguishComment(serverCommentId: Components.Schemas.CommentID(serverCommentId), distinguished: distinguished)
                Haptics.success()
            } catch {
                alertService.handle(error, for: .distinguishComment)
            }
        }
    }

    private func promptBanFromCommunity(serverPersonId: Int64, userName: String?) {
        guard let headerRow else { return }
        let communityId = Components.Schemas.CommunityID(headerRow.serverCommunityId)
        presentBanFromCommunityConfirmation(
            userName: userName ?? NSLocalizedString("this user", comment: "Fallback user name in ban confirmation"),
            communityName: headerRow.communityName
        ) { [weak self] removeData, reason in
            self?.performBanFromCommunity(
                communityId: communityId,
                serverPersonId: Components.Schemas.PersonID(serverPersonId),
                removeData: removeData,
                reason: reason
            )
        }
    }

    private func performBanFromCommunity(
        communityId: Components.Schemas.CommunityID,
        serverPersonId: Components.Schemas.PersonID,
        removeData: Bool,
        reason: String?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            Haptics.tap()
            do {
                try await accountService
                    .lemmyService(forAccountKeychainId: viewModel.accountKeychainId)
                    .banFromCommunity(
                        serverCommunityId: communityId,
                        serverPersonId: serverPersonId,
                        ban: true,
                        removeData: removeData,
                        reason: reason
                    )
                Haptics.success()
            } catch {
                alertService.handle(error, for: .banFromCommunity)
            }
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
            presentSignInGate(
                title: NSLocalizedString("Sign in to comment", comment: "Sign-in gate title when a signed-out user tries to comment")
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
                        preloadedImage: currentImage,
                        altText: self?.headerRow?.altText
                    )
                }
                cell.videoTapped = { [weak self] videoUrl in
                    self?.presentVideoPlayer(url: videoUrl)
                }
                cell.openInBrowser = { [weak self] url in
                    guard let self else { return }
                    Task { await appService.open(url: url, on: self) }
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
                    postCreatorPersonId: self?.headerRow?.creatorPersonId,
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

                // Swipe slots are user-configurable (M8). Defaults reproduce the
                // prior vote / vote / reply / collapse layout. Collapse is also
                // available via tap; a collapse swipe slot mirrors it for
                // gesture-first users.
                let general = appearance.general
                cell.swipeActionConfiguration = self?.commentSwipeActionConfig.viewConfiguration(
                    state: Self.swipeState(for: row, isCollapsed: isCollapsed),
                    appearance: general
                )

                cell.swipeActionTriggered = { [weak self] trigger in
                    guard let self else { return }
                    let action = commentSwipeActionConfig.action(for: SwipeActionSlot(trigger: trigger))
                    performCommentSwipeAction(
                        action,
                        elementId: elementId,
                        serverCommentId: row.serverCommentId
                    )
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
        // The post header row uses the system default preview; only comment
        // cells get the custom rounded preview.
        guard let cell = cell as? PostDetailCommentCell else { return nil }

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
        // Header row (the post itself): a small menu offering Share and Report.
        if dataSource.itemIdentifier(for: indexPath) == .header {
            return postContextMenuConfiguration(at: indexPath)
        }

        guard
            indexPath.section == 1,
            case let .comment(elementId) = dataSource.itemIdentifier(for: indexPath),
            let commentRow = commentRowsByElementId[elementId],
            let serverCommentId = commentRow.serverCommentId
        else { return nil }

        let isSaved = commentRow.isSaved ?? false
        let isOwnComment = isOwnContent(creatorPersonId: commentRow.creatorPersonId)
        let generalAppearance = appearanceService.general
        return UIContextMenuConfiguration(
            identifier: indexPath as NSCopying,
            previewProvider: nil,
            actionProvider: { [weak self] _ in
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
                var children: [UIMenuElement] = [upvoteAction, downvoteAction, replyAction, saveAction, shareAction]
                // Reporting your own comment is meaningless, so only offer it
                // on other people's content.
                if !isOwnComment {
                    let reportAction = UIAction(
                        title: NSLocalizedString("Report", comment: "Context-menu action to report a comment"),
                        image: UIImage(systemName: "flag"),
                        attributes: .destructive
                    ) { [weak self] _ in
                        self?.reportComment(serverCommentId: serverCommentId)
                    }
                    children.append(reportAction)
                }
                // Moderation submenu, only when the account moderates this
                // community (or is an admin).
                if let modMenu = self?.commentModerationMenu(
                    serverCommentId: serverCommentId,
                    commentRow: commentRow
                ) {
                    children.append(modMenu)
                }
                return UIMenu(title: "", children: children)
            }
        )
    }

    /// Context menu for the post header row: Share, plus Report (hidden for the
    /// account's own post). Mirrors the comment menu's structure.
    private func postContextMenuConfiguration(at indexPath: IndexPath) -> UIContextMenuConfiguration {
        let isOwnPost = isOwnContent(creatorPersonId: headerRow?.creatorPersonId)
        return UIContextMenuConfiguration(
            identifier: indexPath as NSCopying,
            previewProvider: nil,
            actionProvider: { [weak self] _ in
                let shareAction = UIAction(
                    title: NSLocalizedString("Share", comment: "Context-menu action to share a post"),
                    image: UIImage(systemName: "square.and.arrow.up")
                ) { [weak self] _ in
                    self?.sharePost()
                }
                var children: [UIMenuElement] = [shareAction]
                if !isOwnPost {
                    let reportAction = UIAction(
                        title: NSLocalizedString("Report", comment: "Context-menu action to report a post"),
                        image: UIImage(systemName: "flag"),
                        attributes: .destructive
                    ) { [weak self] _ in
                        self?.reportPost()
                    }
                    children.append(reportAction)
                }
                // Moderation submenu, only when the account moderates this
                // post's community (or is an admin).
                if let modMenu = self?.postModerationMenu() {
                    children.append(modMenu)
                }
                return UIMenu(title: "", children: children)
            }
        )
    }
}
