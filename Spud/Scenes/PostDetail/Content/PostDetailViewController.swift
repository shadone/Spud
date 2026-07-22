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
import SpudUtilKit
import SwiftUI
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
        HasLinkEmbedService &
        HasPostContentDetectorService &
        HasPreferencesService &
        HasReachabilityMonitor
    typealias NestedDependencies =
        PersonOrLoadingViewController.Dependencies &
        CommunityOrLoadingViewController.Dependencies &
        InstanceDetailViewController.Dependencies
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

    var linkEmbedService: LinkEmbedServiceType {
        dependencies.own.linkEmbedService
    }

    var postContentDetector: PostContentDetectorServiceType {
        dependencies.own.postContentDetectorService
    }

    var preferencesService: PreferencesServiceType {
        dependencies.own.preferencesService
    }

    var reachabilityMonitor: ReachabilityMonitoring {
        dependencies.own.reachabilityMonitor
    }

    // MARK: - Public

    var serverPostId: Lemmy.PostID {
        viewModel.serverPostId
    }

    func setPost(
        serverPostId: Lemmy.PostID,
        accountKeychainId: String,
        scrollToCommentId: Lemmy.CommentID? = nil
    ) {
        pendingPermalinkServerCommentId = scrollToCommentId.map(Int64.init)
        permalinkHighlightElementIds.removeAll(keepingCapacity: true)
        observationTask?.cancel()
        commentObservationTask?.cancel()
        outboundReactionTask?.cancel()
        loadingObservationTask?.cancel()
        // Deterministically tear down the outgoing view model's data
        // observations (header, comments, and outbound) before it is replaced
        // (the new view model starts fresh).
        viewModel.stopObservations()

        // Drop the previous post's reveal state so the blur is always shown for
        // the newly-loaded post until the user explicitly taps to reveal.
        headerNsfwRevealed = false
        updateHeaderPrivacy()

        // Drop the previous post's pending overlay so a stale outbound comment
        // can't splice into the new post's tree before the new outbound
        // observation's first emit (iPad detail-column reuse path). The pending
        // rows themselves now live on the view model, so they reset with the new
        // view model constructed below; only these VC-derived lookup dictionaries
        // still need clearing here.
        pendingStateByElementId.removeAll(keepingCapacity: true)
        pendingTokenByElementId.removeAll(keepingCapacity: true)
        editOverlayByElementId.removeAll(keepingCapacity: true)

        viewModel = PostDetailViewModel(
            serverPostId: serverPostId,
            accountScope: dependencies.own.accountService.scope(forAccountKeychainId: accountKeychainId),
            appDatabase: dependencies.own.appDatabase,
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
        tableView.register(PostDetailNewSinceBannerCell.self, forCellReuseIdentifier: PostDetailNewSinceBannerCell.reuseIdentifier)
        tableView.register(PostDetailCrossPostsCell.self, forCellReuseIdentifier: PostDetailCrossPostsCell.reuseIdentifier)
        tableView.register(PostDetailCommentCell.self, forCellReuseIdentifier: PostDetailCommentCell.reuseIdentifier)
        tableView.register(PostDetailCommentLoadingCell.self, forCellReuseIdentifier: PostDetailCommentLoadingCell.reuseIdentifier)
        tableView.register(PostDetailEmptyCommentsCell.self, forCellReuseIdentifier: PostDetailEmptyCommentsCell.reuseIdentifier)
        tableView.register(PostDetailCommentsFailedCell.self, forCellReuseIdentifier: PostDetailCommentsFailedCell.reuseIdentifier)
        tableView.register(PostDetailLoadMoreCommentsCell.self, forCellReuseIdentifier: PostDetailLoadMoreCommentsCell.reuseIdentifier)
        return tableView
    }()

    lazy var refreshControl: UIRefreshControl = {
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(reloadData), for: .valueChanged)
        return refreshControl
    }()

    /// Floating control that scrolls to the next top-level (depth-1) comment so
    /// users can skim threads fast. When there are new comments it targets the
    /// next new comment instead. Hidden when there is nothing to jump to below
    /// the current scroll position.
    lazy var jumpToNextButton: UIButton = {
        let button = UIButton(configuration: UIButton.Configuration.filled())
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityIdentifier = "jumpToNextTopComment"
        button.addTarget(self, action: #selector(jumpToNextTopCommentTapped), for: .touchUpInside)
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.2
        button.layer.shadowRadius = 6
        button.layer.shadowOffset = CGSize(width: 0, height: 2)
        button.alpha = 0
        button.isHidden = true
        applyDefaultJumpButtonStyle(to: button)
        return button
    }()

    // MARK: - Public

    /// Fires when the observed post flips to a gone state (removed / deleted by
    /// someone else / `couldnt_find_post`) and the current account is not a
    /// moderator or the author. The parent swaps in the unavailable placeholder.
    var didBecomeUnavailable: ((PostUnavailableReason) -> Void)?

    // MARK: - Private

    // internal: shared with PostDetailViewController+Content / +Report / +DeleteRestore / +Moderation / +PendingComments / +OverflowMenu
    var viewModel: PostDetailViewModel
    /// The body string last pre-warmed into `MarkdownBlockCache` off the main
    /// thread. The header observation re-emits on every vote/save with the same
    /// body, so this skips the redundant background hop on those updates while
    /// still warming the cache once when the body first arrives (or changes).
    private var prewarmedHeaderBody: String?
    /// Synthetic-element-id -> cell state, rebuilt each `applySnapshot()`. A
    /// synthetic id is a large negative number (see `pendingElementId(for:)`)
    /// so it never collides with a real `commentElement.id`. The cell provider
    /// and tap handler resolve a synthetic id through this map.
    // internal: shared with PostDetailViewController+PendingComments
    var pendingStateByElementId: [Int64: PendingCommentCellState] = [:]
    /// Synthetic-element-id -> outbound `clientToken`, for the Retry / Edit /
    /// Discard tap actions on a failed pending comment.
    // internal: shared with PostDetailViewController+PendingComments
    var pendingTokenByElementId: [Int64: String] = [:]
    /// Real-comment-element-id -> pending EDIT overlay, rebuilt each
    /// `applySnapshot()`. Unlike a pending reply (a new synthetic node), an edit
    /// overlays the new body + a sending/failed indicator onto the EXISTING
    /// server comment row, keeping its votes/score/badges/children. Cleared on
    /// success when the outbound row is deleted and the server body lands.
    // internal: shared with PostDetailViewController+PendingComments
    var editOverlayByElementId: [Int64: PendingCommentEditOverlay] = [:]
    /// Element ids of new comments whose one-time fresh-wash fade has already
    /// played this visit, so scrolling them back into view doesn't replay it.
    private var animatedNewCommentIds: Set<Int64> = []
    /// A comment the screen was opened to anchor on (a `/comment/<id>` permalink).
    /// Held as the Lemmy server comment id until the matching row appears in the
    /// loaded tree, then resolved to its element id, scrolled to, and cleared
    /// (one-shot). See ``attemptPermalinkScroll()``.
    private var pendingPermalinkServerCommentId: Int64?
    /// Element ids to flash once when their cell next displays, so a permalink
    /// target washes the accent tint on arrival without being treated as a
    /// "new since last visit" comment.
    private var permalinkHighlightElementIds: Set<Int64> = []
    /// The `isNew` styling currently applied to the jump FAB, so the per-scroll
    /// `updateJumpButtonVisibility` only rebuilds the button configuration when
    /// the style actually flips (not on every scroll tick).
    private var jumpButtonIsNewStyle: Bool?
    /// The backing account's moderation capability, refreshed from the server
    /// on appearance. Drives whether mod actions show in the context menus.
    /// `.none` until the first fetch (and for signed-out accounts).
    // internal: shared with PostDetailViewController+Moderation
    var moderationCapability: ModerationCapability = .none
    /// True once `refreshModerationCapability()` has completed its async fetch.
    /// Until then the removed/deleted placeholder decision is deferred (see
    /// `PostUnavailableReason.forHeader`) to avoid racing a moderator/author
    /// out of their Restore access.
    private var moderationCapabilityResolved = false
    /// Guards `didBecomeUnavailable` so the placeholder fires at most once,
    /// whether triggered by an observed row or by the capability resolving.
    private var didFirePlaceholder = false
    /// Per-collapsed-parent hidden-descendant counts from the last visible-tree
    /// computation. Used to render the "+N" badge on collapsed cells.
    private var collapsedDescendantCounts: [Int64: Int] = [:]
    private var collapsedNewDescendantCounts: [Int64: Int] = [:]
    /// Comment elements whose blocked author the user chose to reveal.
    private var revealedBlockedElementIds: Set<Int64> = []
    private var observationTask: Task<Void, Never>?
    private var commentObservationTask: Task<Void, Never>?
    /// Reacts to the view model's published `pendingOutboundComments` (kept live
    /// by the outbound GRDB observation the view model owns) and re-applies the
    /// comment snapshot on each change. See `startOutboundReaction()`.
    private var outboundReactionTask: Task<Void, Never>?
    private var swipeActionsObservationTask: Task<Void, Never>?
    private var configBarButtonItem: UIBarButtonItem!
    private let forcePopoverDelegate = ForcePopoverDelegate()
    private var commentDensityObservationTask: Task<Void, Never>?
    private var blurNsfwObservationTask: Task<Void, Never>?
    /// Re-fetches the comment tree the moment connectivity returns, but only when
    /// the last fetch failed. Independent of the backing post/account, so it is
    /// started once in `viewDidLoad` and reads `viewModel` live at fire time
    /// (the view model is swapped on `setPost`).
    private var reachabilityObservationTask: Task<Void, Never>?
    /// True once the user has tapped to reveal the NSFW blur for the currently-open
    /// post. Reset to false whenever a different post loads.
    private var headerNsfwRevealed = false
    /// Whether the screen is currently on-screen; gates the privacy registration.
    private var isViewVisible = false
    /// Privacy-screen registration: a revealed NSFW header image is sensitive, so it
    /// is hidden from the app-switcher snapshot and screen capture (see PrivacyScreen).
    private let sensitiveContentToken = SensitiveContentToken()
    /// True once the comment GRDB observation has emitted at least once; gates
    /// the single `didPrepareObservation` call.
    private var hasReceivedFirstCommentSnapshot = false
    /// True once a comment fetch has completed (its loading flag went
    /// true -> false); gates the "No comments yet" empty state.
    private var hasCompletedCommentFetch = false
    private var loadingObservationTask: Task<Void, Never>?

    /// The active comment swipe-action config, sanitized for comments. Seeded
    /// from the preference and kept live via `swipeActionsObservationTask`;
    /// changes reconfigure visible comment cells.
    private var commentSwipeActionConfig: SwipeActionConfig = .defaultComments

    // internal: shared with PostDetailViewController+PendingComments
    var dataSource: UITableViewDiffableDataSource<Section, Item>!
    private var isFirstAppearance: Bool = true

    /// Fun stats: accumulates user scroll distance; reported in batches.
    private var scrollOdometer = ScrollOdometer()
    // internal: shared with PostDetailViewController+OverflowMenu
    var overflowBarButtonItem: UIBarButtonItem!

    // MARK: Functions

    init(
        serverPostId: Lemmy.PostID,
        accountKeychainId: String,
        scrollToCommentId: Lemmy.CommentID? = nil,
        dependencies: Dependencies
    ) {
        self.dependencies = (own: dependencies, nested: dependencies)
        pendingPermalinkServerCommentId = scrollToCommentId.map(Int64.init)
        viewModel = PostDetailViewModel(
            serverPostId: serverPostId,
            accountScope: dependencies.accountService.scope(forAccountKeychainId: accountKeychainId),
            appDatabase: dependencies.appDatabase,
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

    /// `isolated deinit` so the body runs on the main actor: `stopObservations()`
    /// is main-actor isolated, and a live observation task can outlive the
    /// controller (it strong-holds the view model), so this must be able to reach
    /// the view model to cancel it.
    isolated deinit {
        observationTask?.cancel()
        commentObservationTask?.cancel()
        outboundReactionTask?.cancel()
        swipeActionsObservationTask?.cancel()
        commentDensityObservationTask?.cancel()
        blurNsfwObservationTask?.cancel()
        loadingObservationTask?.cancel()
        reachabilityObservationTask?.cancel()
        // Symmetry with `setPost`: proactively tear down the view model's own
        // data observations so they don't outlive the controller. (The view
        // model's `deinit` also cancels them, but that only runs once no live
        // observation task is still strong-holding it.)
        viewModel.stopObservations()
    }

    private func setup() {
        // Build the diffable data source before any `view` access below triggers
        // `loadView` -> `viewDidLoad` -> `startObservations()` -> `applySnapshot()`,
        // which requires a non-nil `dataSource`.
        setupDataSource()

        view.backgroundColor = Theme.background

        overflowBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis"),
            menu: makePostOverflowMenu()
        )
        overflowBarButtonItem.accessibilityIdentifier = "postOverflowMenu"
        overflowBarButtonItem.accessibilityLabel = NSLocalizedString(
            "More",
            comment: "Accessibility label for the post detail overflow menu button"
        )
        configBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "slider.horizontal.3"),
            style: .plain,
            target: self,
            action: #selector(configTapped)
        )
        configBarButtonItem.accessibilityIdentifier = "postDetailConfig"
        configBarButtonItem.accessibilityLabel = NSLocalizedString(
            "Comment options",
            comment: "Accessibility label for the post detail comment config button"
        )
        navigationItem.rightBarButtonItems = [overflowBarButtonItem, configBarButtonItem]

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
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        startSwipeActionsObservation()
        startCommentDensityObservation()
        startBlurNsfwObservation()
        startReachabilityObservation()
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
        // Only real comment rows carry per-row state. Exclude the loading
        // skeleton row: reconfiguring it would restart its pulse animation.
        let commentItems = snapshot.itemIdentifiers(inSection: .comments).filter {
            if case .comment = $0 { return true }
            return false
        }
        guard !commentItems.isEmpty else { return }
        snapshot.reconfigureItems(commentItems)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    @objc
    private func configTapped() {
        Haptics.tap()
        let configViewModel = PostDetailConfigViewModel(
            preferencesService: preferencesService,
            currentSort: viewModel.commentSortType,
            onSelectSort: { [weak self] sortType in
                self?.changeCommentSort(to: sortType)
            }
        )
        let host = UIHostingController(rootView: PostDetailConfigView(viewModel: configViewModel))
        host.modalPresentationStyle = .popover
        host.sizingOptions = [.preferredContentSize]
        if let popover = host.popoverPresentationController {
            popover.sourceItem = configBarButtonItem
            popover.delegate = forcePopoverDelegate
        }
        present(host, animated: true)
    }

    /// Applies a new comment sort: updates the view model, restarts the comment
    /// observation with the new ordering, and triggers a cancel-and-replace
    /// fetch. Per-post only — the global default is untouched.
    private func changeCommentSort(to sortType: Lemmy.CommentSortType) {
        guard sortType != viewModel.commentSortType else { return }
        // The view model applies the sort and restarts its comment observation
        // (re-resolving the row id, in case the post was mirrored since open).
        // The VC's revision reaction keeps observing across the restart, so the
        // new ordering's first emit flows through the same pipeline.
        viewModel.restartComments(sortType: sortType)
        Task { await viewModel.fetchComments() }
    }

    /// Observes the comment-density preference and reconfigures visible comment
    /// cells when it changes, so the open thread re-flows live. Independent of
    /// the backing post, so it is started once in `viewDidLoad`.
    private func startCommentDensityObservation() {
        commentDensityObservationTask?.cancel()
        commentDensityObservationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var current = preferencesService.commentDensity
            for await density in preferencesService.commentDensityStream {
                if Task.isCancelled { break }
                guard density != current else { continue }
                current = density
                reconfigureVisibleComments()
            }
        }
    }

    /// Observes the blur-NSFW preference and reconfigures the header cell when it
    /// changes. Independent of the backing post, so it is started once in `viewDidLoad`.
    private func startBlurNsfwObservation() {
        blurNsfwObservationTask?.cancel()
        blurNsfwObservationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var current = preferencesService.blurNsfw
            for await blurNsfw in preferencesService.blurNsfwStream {
                if Task.isCancelled { break }
                guard blurNsfw != current else { continue }
                current = blurNsfw
                guard dataSource != nil else { continue }
                var snapshot = dataSource.snapshot()
                snapshot.reconfigureItems([.header])
                await dataSource.apply(snapshot, animatingDifferences: false)
            }
        }
    }

    /// Auto-retries the comment fetch when connectivity returns, but only on the
    /// offline -> online edge and only when the last fetch failed. This is what
    /// makes the offline failed-state copy ("Spud will retry automatically when
    /// you're back online") true — without it only the manual Retry button worked.
    /// Mirrors the feed's `reachabilityObservationTask` in `PostListViewController`.
    ///
    /// The retry decision (`CommentsReconnectRetry.shouldRetry`) gates on both the
    /// `false -> true` reachability edge and `commentFetchError != nil`. The
    /// `statusStream` replays its current value on subscribe, so the previous
    /// value is tracked to skip that non-edge first emission. `fetchComments()` is
    /// cancel-and-replace and clears the error the moment it starts, so it neither
    /// double-fetches alongside the normal appear/load path nor loops on a
    /// non-network failure (e.g. malformed response): the error guard limits the
    /// retry to one per reconnect, and a re-failed fetch only retries on the next
    /// reconnect. Independent of the backing post/account, so it is started once
    /// in `viewDidLoad` and reads `viewModel` live (the model is swapped on
    /// `setPost`).
    private func startReachabilityObservation() {
        reachabilityObservationTask?.cancel()
        reachabilityObservationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var wasOnline = reachabilityMonitor.isOnline
            for await online in reachabilityMonitor.statusStream {
                if Task.isCancelled { break }
                let shouldRetry = CommentsReconnectRetry.shouldRetry(
                    isOnline: online,
                    wasOnline: wasOnline,
                    hasFetchError: viewModel.commentFetchError != nil
                )
                wasOnline = online
                guard shouldRetry else { continue }
                let viewModel = viewModel
                Task { await viewModel.fetchComments() }
            }
        }
    }

    /// Reconfigures visible comment cells so they rebuild body views at the
    /// updated density.
    private func reconfigureVisibleComments() {
        guard dataSource != nil else { return }
        var snapshot = dataSource.snapshot()
        // Only real comment rows carry per-row state. Exclude the loading
        // skeleton row: reconfiguring it would restart its pulse animation.
        let commentItems = snapshot.itemIdentifiers(inSection: .comments).filter {
            if case .comment = $0 { return true }
            return false
        }
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

        isViewVisible = true
        updateHeaderPrivacy()
        updateUserActivity()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        isViewVisible = false
        updateHeaderPrivacy()
        userActivity?.resignCurrent()
        userActivity = nil
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        reportScrollDistanceIfNeeded(force: true)
    }

    /// A revealed NSFW header image counts as sensitive content on screen. Call on
    /// every change to the inputs (visibility, reveal, the loaded post).
    private func updateHeaderPrivacy() {
        sensitiveContentToken.set(isViewVisible && headerNsfwRevealed && (viewModel.headerRow?.isNsfw ?? false))
    }

    /// Vends a Handoff/Spotlight/Prediction activity for this post, keyed by its
    /// canonical `ap_id` so it resolves under any account on any device.
    ///
    /// Deferred until the header GRDB row is known: `headerRow` is usually still
    /// nil at `viewDidAppear` (the observation publishes a beat later), and the
    /// NSFW flag lives on that row. Waiting for it — rather than advertising
    /// eagerly and correcting later — means an NSFW post is never advertised to
    /// Handoff/Spotlight/Siri, not even momentarily. `SpudUserActivity.viewPost`
    /// itself refuses to build an activity when the row is flagged NSFW.
    ///
    /// Re-invoked on every header GRDB emission (vote/save/edit), so it must also
    /// handle the post being edited to NSFW while already on screen: an
    /// already-vended activity is revoked the moment the row flips NSFW, not just
    /// refused at first vend. Also gated on `isViewVisible` so the observation
    /// loop can't re-vend a non-NSFW post's activity while the VC is alive but
    /// not currently on screen.
    private func updateUserActivity() {
        // Only advertise a post to Handoff/Spotlight/Siri while it's on screen AND known to be
        // non-NSFW. headerRow arrives via the GRDB observation a beat after viewDidAppear and can
        // change if the post is edited on-screen, so this is re-invoked from the header observation
        // loop and MUST re-evaluate NSFW every time — including revoking an already-vended activity
        // if the post becomes NSFW. Never surface sensitive posts to these off-device/system surfaces.
        guard isViewVisible else { return }
        guard let headerRow = viewModel.headerRow else { return } // NSFW status not known yet

        if headerRow.isNsfw {
            userActivity?.resignCurrent()
            userActivity = nil
            return
        }

        guard userActivity == nil else { return } // already advertising this non-NSFW post

        let instanceActorId = viewModel.instanceActorId
        guard let canonical = LinkURL.forPost(
            instance: .originalInstance,
            originalPostUrl: headerRow.originalPostUrl,
            serverPostId: Int64(viewModel.serverPostId),
            instanceActorId: instanceActorId
        ) else { return }
        let routingURL = URL.SpudInternalLink.objectAtURL(url: canonical).url
        guard let activity = SpudUserActivity.viewPost(
            routingURL: routingURL,
            title: headerRow.title,
            isNsfw: headerRow.isNsfw
        ) else { return }
        userActivity = activity
        activity.becomeCurrent()
    }

    private func markAsRead() async {
        do {
            try await viewModel.markAsRead()
        } catch {
            alertService.handle(error, for: .markAsRead)
        }
    }

    /// Refreshes the backing account's moderation capability from the server.
    /// Best-effort: a failure (or signed-out account) leaves the capability at
    /// `.none`, simply hiding mod actions.
    private func refreshModerationCapability() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let capability = await (
                try? viewModel.fetchModerationCapability()
            ) ?? .none
            guard !Task.isCancelled else { return }
            moderationCapability = capability
            moderationCapabilityResolved = true
            // A row may have already arrived while the capability was still
            // resolving (it was deferred); re-evaluate it now.
            reevaluateUnavailability()
        }
    }

    private func startObservations() {
        hasReceivedFirstCommentSnapshot = false
        hasCompletedCommentFetch = false
        startLoadingObservation()
        // Lay down the skeleton row at open. `dataSource` exists (it is created in
        // setupDataSource() from loadView, before startObservations()).
        applySnapshot()

        refreshModerationCapability()

        // The outbound (pending/failed) overlay is keyed on serverPostId in the
        // view model, so it works even before the post is mirrored — start the
        // reaction here, before the postRowId gate below (the view model starts
        // the matching observation in `startObservations()`).
        startOutboundReaction()

        // The view model owns the header GRDB observation + visit recording: it
        // resolves the post's local row id, records the visit, and starts
        // publishing `headerRow`. When the post is not yet mirrored it fires the
        // initial comment fetch itself and leaves `postRowId` nil.
        viewModel.startObservations()

        guard viewModel.postRowId != nil else {
            // Post not yet mirrored; the view model already kicked a comment
            // fetch that dual-writes everything the observations need.
            return
        }

        // React to the view model's published header row, reproducing the
        // per-emit view pipeline (unavailability, header privacy, overflow-menu
        // rebuild, body prewarm, snapshot) in the same order as before — now
        // driven by the observation stream instead of the GRDB loop directly.
        observationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await headerRow in ObservationStream.values(of: { [weak self] in
                self?.viewModel.headerRow
            }) {
                if Task.isCancelled { break }
                reevaluateUnavailability()
                if didFirePlaceholder { break }
                updateHeaderPrivacy()
                // A late-arriving header (the common case: nil at viewDidAppear)
                // is what actually advertises the activity for most opens.
                updateUserActivity()
                // Rebuild so the Save/Unsave label, Mute target, and the
                // own-post-gated Report/Block items reflect the latest row.
                overflowBarButtonItem.menu = makePostOverflowMenu()
                // Parse the body off the main thread before the header cell is
                // configured, so its dequeue is a warm cache hit instead of a
                // synchronous parse. Only on a new/changed body (not on every
                // vote/save re-emit), and skipped if cancelled mid-parse.
                if let body = headerRow?.body, !body.isEmpty, body != prewarmedHeaderBody {
                    await MarkdownBlockCache.shared.prewarm(body)
                    if Task.isCancelled { break }
                    prewarmedHeaderBody = body
                }
                applySnapshot()
            }
        }

        startCommentReaction()
    }

    /// Reacts to the view model's published `commentsRevision`, reproducing the
    /// per-emit comment pipeline the GRDB loop used to run inline — in the same
    /// order: prewarm the comment bodies off the main thread, apply the snapshot,
    /// attempt the permalink scroll, then fire the one-shot `didPrepareObservation`.
    /// The view model owns the GRDB observation now: on each emit it stores the
    /// tree into `orderedComments` (`@ObservationIgnored`) — rebuilding its
    /// `commentRowsByElementId` element-id lookup atomically in the same turn — and
    /// bumps `commentsRevision`, so that counter — not the tree — is the reaction
    /// key. Because the lookup lives on the view model alongside the tree, an
    /// `applySnapshot()` that interleaves during this reaction's `await` always
    /// sees a lookup consistent with the tree it renders.
    private func startCommentReaction() {
        commentObservationTask?.cancel()
        commentObservationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // The stream yields synchronously on subscribe (revision 0, before
            // any DB emit). Skip that seed value: only the increments a real DB
            // emit produces count as a comment snapshot.
            var lastHandledRevision = 0
            for await revision in ObservationStream.values(of: { [weak self] in
                self?.viewModel.commentsRevision ?? 0
            }) {
                if Task.isCancelled { break }
                guard revision != lastHandledRevision else { continue }
                lastHandledRevision = revision

                let rows = viewModel.orderedComments

                await Self.prewarmCommentBodies(
                    rows,
                    textSizeAdjustment: appearanceService.postDetail.textSizeAdjustment
                )
                if Task.isCancelled { break }

                applySnapshot()
                attemptPermalinkScroll()
                if !hasReceivedFirstCommentSnapshot {
                    hasReceivedFirstCommentSnapshot = true
                    viewModel.didPrepareObservation(numberOfFetchedComments: rows.count)
                }
            }
        }
    }

    /// Fires the unavailable placeholder for the current header row if the
    /// gating rule now warrants it. Fires at most once.
    private func reevaluateUnavailability() {
        guard !didFirePlaceholder, let headerRow = viewModel.headerRow, let reason = unavailableReason(for: headerRow) else {
            return
        }
        didFirePlaceholder = true
        didBecomeUnavailable?(reason)
    }

    /// Maps an observed header row to the placeholder reason, or nil to keep the
    /// content. Mods keep removed posts; authors keep their own deleted posts.
    private func unavailableReason(for row: PostDetailHeaderRow) -> PostUnavailableReason? {
        let canModerate = moderationCapability.canModerate(
            communityId: Lemmy.CommunityID(row.serverCommunityId)
        )
        let isOwnPost = row.creatorPersonId == viewModel.currentAccountPersonId
        return PostUnavailableReason.forHeader(
            isRemoved: row.isRemoved,
            isDeleted: row.isDeleted,
            isUnavailable: row.isUnavailable,
            canModerate: canModerate,
            isOwnPost: isOwnPost,
            moderationCapabilityResolved: moderationCapabilityResolved
        )
    }

    /// If the screen was opened on a `/comment/<id>` permalink, try to resolve the
    /// target server comment id to a loaded element id and scroll to it. Called
    /// after every comment-snapshot apply: the target may not be in the local DB on
    /// the first emit (a fresh permalink), so this no-ops until the network fetch
    /// lands and the observation re-fires with the row present. One-shot — clears
    /// the pending target once it scrolls, and queues a one-time highlight flash.
    private func attemptPermalinkScroll() {
        guard
            let target = pendingPermalinkServerCommentId,
            let elementId = viewModel.commentRowsByElementId.values
            .first(where: { $0.serverCommentId == target })?.id
        else { return }
        pendingPermalinkServerCommentId = nil
        permalinkHighlightElementIds.insert(elementId)
        scrollToComment(elementId: elementId)
        // If the row is already on screen, `willDisplay` won't fire for it — flash now.
        if
            let indexPath = dataSource.indexPath(for: .comment(elementId: elementId)),
            let cell = tableView.cellForRow(at: indexPath) as? PostDetailCommentCell,
            permalinkHighlightElementIds.remove(elementId) != nil
        {
            cell.playPermalinkHighlight()
        }
    }

    /// Reacts to the view model's published outbound (pending/failed) comment
    /// rows — which it keeps live via the GRDB outbound observation it owns — and
    /// re-applies the snapshot when they change, so locally-composed comments
    /// appear inline while sending and flip to a normal comment (the row is
    /// deleted on success, which removes the overlay node) once the server
    /// confirms. Draft rows never reach here (the view model filters them out).
    /// Keyed on `serverPostId` in the view model, so unlike the comment
    /// observation it does not need the post to be mirrored yet.
    private func startOutboundReaction() {
        outboundReactionTask?.cancel()
        outboundReactionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // `ObservationStream` yields the current value synchronously on
            // subscribe (before the view model's outbound observation has
            // delivered anything). Skip that seed: only an actual change to the
            // published rows — i.e. a real DB emit through the view model — is a
            // pending-overlay update, matching the old inline observation that
            // ran `applySnapshot` once per DB emit (and no extra time on
            // bring-up).
            var isSeed = true
            for await _ in ObservationStream.values(of: { [weak self] in
                self?.viewModel.pendingOutboundComments ?? []
            }) {
                if Task.isCancelled { break }
                if isSeed {
                    isSeed = false
                    continue
                }
                applySnapshot(animated: true)
            }
        }
    }

    /// Observes the view model's comment-loading flag and fetch-error and
    /// re-applies the snapshot on each change (so the loading-skeleton /
    /// failed-state / empty-state placeholder rows are added/removed), recording
    /// the first fetch completion (the loading true -> false edge) so the empty
    /// state can show only once a fetch settles. The error is tracked alongside
    /// the loading flag (both are read in the closure, so Observation re-fires on
    /// either) so the inline failed state appears/clears even when the loading
    /// flag did not change in the same step.
    private func startLoadingObservation() {
        loadingObservationTask?.cancel()
        loadingObservationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var wasLoading = false
            for await state in ObservationStream.values(of: { [weak self] in
                LoadingObservationState(
                    isLoading: self?.viewModel.isLoadingComments ?? false,
                    hasError: self?.viewModel.commentFetchError != nil
                )
            }) {
                if Task.isCancelled { break }
                if wasLoading, !state.isLoading {
                    hasCompletedCommentFetch = true
                }
                wasLoading = state.isLoading
                // The skeleton, failed, and empty-state are rows now: re-apply the
                // snapshot so the placeholder is added or removed as the loading
                // flag flips or a fetch error appears/clears.
                applySnapshot()
            }
        }
    }

    /// The pair of comment-fetch states the loading observation watches. Reduced
    /// to `Equatable` flags (not the `LoadFailure` itself) so the stream only
    /// re-fires on a meaningful transition.
    private struct LoadingObservationState: Equatable {
        let isLoading: Bool
        let hasError: Bool
    }

    /// Items for the comments section given the current placeholder state. Every
    /// placeholder is an in-flow row in the comments section (so it scrolls with
    /// content, below the pinned header, where the comments will appear): the
    /// loading skeleton while a fetch is in flight, the inline "couldn't load
    /// comments" failed-state row when the fetch errored with nothing to show, and
    /// the "No comments yet" empty-state row once a fetch settles with no comments.
    /// `.hidden` (and the defensive case of a placeholder with comments somehow
    /// present) passes the comment rows through unchanged.
    static func commentsSectionItems(
        background: CommentsBackground,
        commentItems: [Item]
    ) -> [Item] {
        switch background {
        case .skeleton:
            return [.commentLoadingSkeleton]
        case .failed where commentItems.isEmpty:
            return [.commentsFailed]
        case .empty where commentItems.isEmpty:
            return [.commentsEmpty]
        case .failed, .empty, .hidden:
            return commentItems
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
        if viewModel.newCommentCount > 0 {
            snapshot.appendItems([.newSinceBanner], toSection: .header)
            snapshot.reconfigureItems([.newSinceBanner])
        }
        if !viewModel.crossPosts.isEmpty {
            snapshot.appendItems([.crossPostedTo], toSection: .header)
            snapshot.reconfigureItems([.crossPostedTo])
        }
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
        collapsedNewDescendantCounts = visible.collapsedNewDescendantCounts

        let background = CommentsBackground.decide(
            isLoadingComments: viewModel.isLoadingComments,
            hasCompletedFetch: hasCompletedCommentFetch,
            hasComments: !viewModel.orderedComments.isEmpty,
            // Only the view-model `fetchComments()` path (initial load, sort
            // change, Retry) sets this. Pull-to-refresh fetches comments directly
            // through LemmyService and never sets `commentFetchError`, so a refresh
            // failure with comments already on screen keeps the list and surfaces a
            // toast instead (see `reloadAsync`) — it never reaches the failed state.
            fetchError: viewModel.commentFetchError
        )
        // Splice pending (locally-composed, not-yet-confirmed) comments into the
        // visible tree: a reply lands right after the loaded row whose server
        // comment id is its parent; a top-level reply (or an orphan whose parent
        // is not loaded) is appended at the end. Synthetic ids never collide with
        // real element ids (see `pendingElementId(for:)`).
        let commentItems = mergedCommentItems(visibleRows: visible.rows)
        let sectionItems = Self.commentsSectionItems(background: background, commentItems: commentItems)
        snapshot.appendItems(sectionItems, toSection: .comments)
        if viewModel.hasOutstandingCommentPages {
            snapshot.appendItems([.commentsLoadMore], toSection: .comments)
            // Reconfigured every pass (like `.newSinceBanner` / `.crossPostedTo`
            // above): the row's own identity never changes, so without this its
            // cell would never re-run `setLoading` when `isLoadingComments`
            // toggles on a re-tap and the spinner would go stale.
            snapshot.reconfigureItems([.commentsLoadMore])
        }
        // Only comment rows need reconfiguring; the skeleton / empty rows have no
        // per-row state. When a placeholder is showing, `commentItems` is empty, so
        // this is a no-op.
        snapshot.reconfigureItems(commentItems)

        let animate = animated && !UIAccessibility.isReduceMotionEnabled
        dataSource.apply(snapshot, animatingDifferences: animate)
        updateJumpButtonVisibility()
    }

    /// The synthetic diffable element id for a pending outbound comment row. A
    /// large negative base keeps it well clear of any real `commentElement.id`
    /// (which are positive), so the two id spaces never collide.
    private static func pendingElementId(for record: OutboundContentRecord) -> Int64 {
        -(1_000_000 + (record.id ?? 0))
    }

    /// Builds the comments-section items: the visible (collapse-filtered) tree
    /// with pending overlay nodes spliced in. Rebuilds `pendingStateByElementId`
    /// / `pendingTokenByElementId` so the cell provider and tap handler can
    /// resolve a synthetic id. A pending reply is placed right after the loaded
    /// row whose `serverCommentId` matches its `parentCommentServerId`; a
    /// top-level reply, or an orphan whose parent is not loaded, is appended at
    /// the end.
    private func mergedCommentItems(visibleRows: [PostDetailCommentRow]) -> [Item] {
        pendingStateByElementId.removeAll(keepingCapacity: true)
        pendingTokenByElementId.removeAll(keepingCapacity: true)
        editOverlayByElementId.removeAll(keepingCapacity: true)

        // No pending rows: the common case stays a plain map (no extra work).
        guard !viewModel.pendingOutboundComments.isEmpty else {
            return visibleRows.map { Item.comment(elementId: $0.id) }
        }

        // Split the pending rows into EDITS (overlay onto an existing comment) and
        // CREATES (a new synthetic node). An edit is identified by
        // `editCommentServerId`; everything else is a create/reply.
        var editByServerCommentId: [Int64: OutboundContentRecord] = [:]
        var createRecords: [OutboundContentRecord] = []
        for record in viewModel.pendingOutboundComments {
            if let editId = record.editCommentServerId {
                // If two edit rows somehow target the same comment, the newest
                // wins (last write reflects the user's latest intent).
                editByServerCommentId[editId] = record
            } else {
                createRecords.append(record)
            }
        }

        // Overlay each pending edit onto its existing visible comment row: record
        // the locally-edited body + sending/failed status keyed by the real
        // element id. The cell provider applies the override at config time (it
        // does NOT mutate `viewModel.commentRowsByElementId`, which stays pristine
        // server data so a later outbound-only snapshot can't compound the override). The
        // row keeps its real element id, so its votes/score/badges/children all
        // stay put; on success the outbound row is deleted and the overlay clears.
        for row in visibleRows {
            guard
                let scid = row.serverCommentId,
                let record = editByServerCommentId[scid]
            else { continue }
            let status: PendingCommentEditOverlay.Status =
                record.status == OutboundStatus.failed.rawValue ? .failed : .sending
            editOverlayByElementId[row.id] = PendingCommentEditOverlay(
                body: record.body,
                status: status,
                clientToken: record.clientToken
            )
        }

        // Server comment ids present in the visible (loaded, non-collapsed-away)
        // tree, so we can tell whether a pending reply's parent is shown.
        var visibleServerCommentIds: Set<Int64> = []
        for row in visibleRows {
            if let scid = row.serverCommentId { visibleServerCommentIds.insert(scid) }
        }

        func pendingItem(for record: OutboundContentRecord, depth: Int) -> Item {
            let elementId = Self.pendingElementId(for: record)
            let status: PendingCommentCellState.Status =
                record.status == OutboundStatus.failed.rawValue ? .failed : .sending
            pendingStateByElementId[elementId] = PendingCommentCellState(
                clientToken: record.clientToken,
                body: record.body,
                depth: depth,
                status: status,
                parentCommentServerId: record.parentCommentServerId
            )
            pendingTokenByElementId[elementId] = record.clientToken
            return .comment(elementId: elementId)
        }

        var mergedItems: [Item] = []
        for row in visibleRows {
            mergedItems.append(.comment(elementId: row.id))
            guard let scid = row.serverCommentId else { continue }
            for record in createRecords where record.parentCommentServerId == scid {
                mergedItems.append(pendingItem(for: record, depth: Int(row.depth) + 1))
            }
        }

        // Top-level pending (no parent) and orphans (parent not in the visible
        // tree) go at the end so they are still reachable. Edits are never added
        // here — they overlay an existing row above.
        for record in createRecords {
            let isTopLevel = record.parentCommentServerId == nil
            let isOrphan = record.parentCommentServerId.map { !visibleServerCommentIds.contains($0) } ?? false
            guard isTopLevel || isOrphan else { continue }
            // True top-level comments (parentCommentServerId == nil) render flush-left
            // at depth 0. Orphan replies whose parent is not visible fall back to
            // depth 1 as a reasonable indent.
            let depth = isTopLevel ? 0 : 1
            mergedItems.append(pendingItem(for: record, depth: depth))
        }

        return mergedItems
    }

    /// Returns a copy of `row` with its body replaced (used to overlay a pending
    /// edit's locally-edited text onto the existing server comment row).
    private static func row(_ row: PostDetailCommentRow, replacingBody body: String) -> PostDetailCommentRow {
        PostDetailCommentRow(
            id: row.id,
            position: row.position,
            depth: row.depth,
            serverCommentId: row.serverCommentId,
            body: body,
            originalCommentUrl: row.originalCommentUrl,
            score: row.score,
            voteStatus: row.voteStatus,
            isSaved: row.isSaved,
            isRemoved: row.isRemoved,
            isDistinguished: row.isDistinguished,
            isDeleted: row.isDeleted,
            isCreatorModerator: row.isCreatorModerator,
            isCreatorAdmin: row.isCreatorAdmin,
            isCreatorBannedFromCommunity: row.isCreatorBannedFromCommunity,
            isCreatorBlocked: row.isCreatorBlocked,
            isCreatorSiteBanned: row.isCreatorSiteBanned,
            isCreatorBot: row.isCreatorBot,
            isCreatorAccountDeleted: row.isCreatorAccountDeleted,
            removedReason: row.removedReason,
            published: row.published,
            creatorName: row.creatorName,
            creatorPersonId: row.creatorPersonId,
            creatorActorId: row.creatorActorId,
            moreChildCount: row.moreChildCount,
            moreParentId: row.moreParentId,
            childCount: row.childCount
        )
    }

    /// Pre-parses every comment body's block tree into `MarkdownBlockCache` off
    /// the main thread for the renderer path. Declared `nonisolated async` so its
    /// body runs on the cooperative pool (Swift 6 language mode) rather than the
    /// main actor; it captures only `Sendable` values (the rows). Cell dequeue
    /// then hits the warm cache instead of parsing cmark on the scroll path.
    private nonisolated static func prewarmCommentBodies(
        _ rows: [PostDetailCommentRow],
        textSizeAdjustment _: CGFloat
    ) async {
        for row in rows {
            if Task.isCancelled { return }
            guard let body = row.body, !body.isEmpty else { continue }
            MarkdownBlockCache.shared.blocks(for: body)
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

    /// Reveals a folded blocked-user comment and reconfigures just that row.
    private func revealBlocked(elementId: Int64) {
        revealedBlockedElementIds.insert(elementId)
        guard dataSource != nil else { return }
        var snapshot = dataSource.snapshot()
        let item = Item.comment(elementId: elementId)
        guard snapshot.indexOfItem(item) != nil else { return }
        snapshot.reconfigureItems([item])
        dataSource.apply(snapshot, animatingDifferences: true)
    }

    // MARK: - Load more replies

    /// Tapping a "load more replies" row: mark it loading, reconfigure the cell to show the
    /// spinner, then fetch + splice. On success the comment observation replaces the row; on
    /// failure revert the row and toast.
    private func handleLoadMoreTap(elementId: Int64, parentServerId: Int64?) {
        guard let parentServerId else { return }
        guard !viewModel.isLoadingMore(elementId: elementId) else { return }

        viewModel.markLoadingMore(elementId: elementId)
        reconfigureCommentRows([elementId])

        Task { [weak self] in
            guard let self else { return }
            do {
                try await viewModel.loadMoreReplies(elementId: elementId, parentServerId: parentServerId)
                // Success: observePostDetailComments emits the spliced tree, and applySnapshot
                // replaces the placeholder row; updateOrderedComments clears the loading flag.
            } catch {
                alertService.handle(error, for: .fetchComments)
                viewModel.clearLoadingMore(elementId: elementId)
                reconfigureCommentRows([elementId])
                showLoadMoreFailureToast()
            }
        }
    }

    /// Re-runs the cell provider for the given comment rows without changing the snapshot's item
    /// set (a loading-flag flip doesn't alter which items exist, so a plain apply won't reconfigure
    /// them).
    private func reconfigureCommentRows(_ elementIds: [Int64]) {
        guard dataSource != nil else { return }
        var snapshot = dataSource.snapshot()
        let items = elementIds
            .map { Item.comment(elementId: $0) }
            .filter { snapshot.indexOfItem($0) != nil }
        guard !items.isEmpty else { return }
        snapshot.reconfigureItems(items)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func showLoadMoreFailureToast() {
        guard let window = view.window else { return }
        ToastPresenter.shared.show(
            NSLocalizedString("Couldn't load more replies", comment: "Toast when loading more comment replies fails"),
            in: window
        )
    }

    // MARK: - Jump to next top-level comment / next new comment

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
            guard viewModel.commentRowsByElementId[elementId]?.depth == 1 else { continue }

            let indexPath = IndexPath(row: offset, section: Section.comments.rawValue)
            let rect = tableView.rectForRow(at: indexPath)
            if rect.minY > threshold {
                return indexPath
            }
        }
        return nil
    }

    /// Scrolls to the comment, first expanding any collapsed ancestors that hide
    /// it (rebuilding the snapshot non-animated) so the row exists before the
    /// scroll. Does not haptic — callers do.
    private func scrollToComment(elementId: Int64) {
        if dataSource.indexPath(for: .comment(elementId: elementId)) == nil {
            if viewModel.expandAncestors(toReveal: elementId) {
                applySnapshot(animated: false)
            }
        }
        guard let indexPath = dataSource.indexPath(for: .comment(elementId: elementId)) else { return }
        tableView.scrollToRow(at: indexPath, at: .top, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    /// Where `elementId` currently sits on screen: its own row if visible, else
    /// the outermost collapsed ancestor — the one still visible in the table
    /// (inner collapsed parents are themselves hidden by it and have no index
    /// path, so the leaf-to-root walk's first resolvable id is that outer one).
    /// Used to position a possibly-hidden new comment for the "below the fold"
    /// test. Returns nil only when neither resolves (should not happen for a
    /// comment in the tree).
    private func anchorIndexPath(forNewComment elementId: Int64) -> IndexPath? {
        if let indexPath = dataSource.indexPath(for: .comment(elementId: elementId)) {
            return indexPath
        }
        let ancestors = CommentCollapseState.collapsedAncestors(
            of: elementId,
            in: viewModel.orderedComments,
            collapsedIds: viewModel.collapsedElementIds
        )
        for ancestorId in ancestors {
            if let indexPath = dataSource.indexPath(for: .comment(elementId: ancestorId)) {
                return indexPath
            }
        }
        return nil
    }

    /// The element id of the next new comment whose anchor row sits below the
    /// current scroll position, in display order. The anchor lets a collapsed-away
    /// new comment still count (positioned at its visible collapsed ancestor); the
    /// jump handler expands it. Returns nil when none below.
    private func nextNewCommentBelowFold() -> Int64? {
        let threshold = tableView.contentOffset.y + tableView.adjustedContentInset.top + 1
        for elementId in viewModel.orderedNewCommentElementIds {
            guard let anchor = anchorIndexPath(forNewComment: elementId) else { continue }
            if tableView.rectForRow(at: anchor).minY > threshold {
                return elementId
            }
        }
        return nil
    }

    /// The FAB's current jump target. A new-comment target is identified by id (it
    /// may be collapsed away and is expanded on tap); a fallback next-top-level
    /// target is a concrete index path.
    private enum JumpTarget {
        case newComment(elementId: Int64)
        case topLevel(indexPath: IndexPath)

        var isNew: Bool {
            if case .newComment = self { return true }
            return false
        }
    }

    private func jumpTarget() -> JumpTarget? {
        if viewModel.newCommentCount > 0, let elementId = nextNewCommentBelowFold() {
            return .newComment(elementId: elementId)
        }
        if let indexPath = indexPathOfNextTopLevelComment() {
            return .topLevel(indexPath: indexPath)
        }
        return nil
    }

    @objc
    private func jumpToNextTopCommentTapped() {
        guard let target = jumpTarget() else { return }
        Haptics.tap()
        switch target {
        case let .newComment(elementId):
            scrollToComment(elementId: elementId)
        case let .topLevel(indexPath):
            tableView.scrollToRow(at: indexPath, at: .top, animated: !UIAccessibility.isReduceMotionEnabled)
        }
    }

    /// Scrolls to the first new comment (the banner's "Jump" action).
    private func jumpToFirstNewComment() {
        guard let elementId = viewModel.firstNewCommentElementId else { return }
        Haptics.tap()
        scrollToComment(elementId: elementId)
    }

    /// Shows the jump button when there is a next top-level or next new comment
    /// below the current scroll position. Restyled for the new-comment case.
    /// Animated unless reduce-motion is on.
    private func updateJumpButtonVisibility() {
        let target = jumpTarget()
        let shouldShow = target != nil

        // Restyle for "Next new" vs the default next-top-level affordance.
        applyJumpButtonStyle(isNew: target?.isNew ?? false)

        guard shouldShow != (jumpToNextButton.alpha > 0) else { return }
        if shouldShow { jumpToNextButton.isHidden = false }
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

    /// Styles the jump FAB for the default next-top-level affordance.
    /// Called from both the lazy initializer and `applyJumpButtonStyle(isNew:)`.
    private func applyDefaultJumpButtonStyle(to button: UIButton) {
        var config = UIButton.Configuration.filled()
        config.image = UIImage(systemName: "chevron.down")
        config.cornerStyle = .capsule
        config.baseBackgroundColor = .secondarySystemBackground
        config.baseForegroundColor = .label
        config.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
        button.configuration = config
        button.accessibilityLabel = NSLocalizedString(
            "Next top-level comment",
            comment: "Accessibility label for the jump-to-next-comment button"
        )
    }

    /// Styles the jump FAB: accent "Next new" label when there are new comments
    /// to jump to, else the default next-top-level chevron.
    private func applyJumpButtonStyle(isNew: Bool) {
        guard isNew != jumpButtonIsNewStyle else { return }
        jumpButtonIsNewStyle = isNew
        let accent = tableView.tintColor ?? .systemTeal
        if isNew {
            var config = UIButton.Configuration.filled()
            config.title = NSLocalizedString("Next new", comment: "Jump to the next new comment")
            config.image = UIImage(systemName: "chevron.down")
            config.imagePlacement = .trailing
            config.imagePadding = 6
            config.cornerStyle = .capsule
            config.baseBackgroundColor = accent
            config.baseForegroundColor = .white
            config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
            jumpToNextButton.configuration = config
            jumpToNextButton.accessibilityLabel = NSLocalizedString(
                "Next new comment",
                comment: "VoiceOver: jump to the next new comment"
            )
        } else {
            applyDefaultJumpButtonStyle(to: jumpToNextButton)
        }
    }

    @objc
    private func reloadData() {
        Task { await reloadAsync() }
    }

    private func reloadAsync() async {
        // Pull-to-refresh is an explicit "refresh everything" gesture, so it
        // refreshes the post itself (getPost) as well as its comments
        // (getComments). The header's comment count lives on the post record,
        // which only a fresh PostView updates — Lemmy's getComments response
        // carries no post counters — so without the getPost the header would
        // stay stale here. Run both concurrently; the post refresh is
        // best-effort so it can't mask a comment-load failure.
        async let postInfoRefresh: Void = refreshPostInfo()
        do {
            try await viewModel.refreshComments()
        } catch {
            alertService.handle(error, for: .fetchComments)
        }
        await postInfoRefresh
        // `refreshPostInfo()` re-reads `viewModel.crossPosts` as a plain
        // one-shot assignment (not a GRDB observation), so it doesn't itself
        // trigger a reaction loop's `applySnapshot()`. The header-row
        // observation happens to cover most refreshes (a fresh PostView
        // usually changes score/comment-count columns too), but a refresh
        // whose ONLY delta is a gained/lost cross-post wouldn't touch those
        // columns and so wouldn't re-emit. Apply explicitly (non-animated, the
        // default) so the section is deterministic rather than riding along on
        // an unrelated observation.
        applySnapshot()
        refreshControl.endRefreshing()
    }

    /// Best-effort refresh of the post record (header counters) on pull-to-refresh.
    /// Failures are swallowed so they don't mask the comment-load error surface.
    private func refreshPostInfo() async {
        do {
            try await viewModel.refreshPostInfo()
        } catch {
            // Comments are the primary content of a post-detail refresh; a
            // header-counter refresh failure should not raise its own alert.
        }
    }

    // internal: shared with PostDetailViewController+OverflowMenu
    func openInBrowser() {
        appService.openInBrowser(
            serverPostId: viewModel.serverPostId,
            originalPostUrl: viewModel.headerRow?.originalPostUrl,
            accountKeychainId: viewModel.accountKeychainId,
            on: self
        )
    }

    /// Shares the current post's canonical URL. Prefers the post's `ap_id`
    /// permalink; falls back to constructing it from the account instance.
    // internal: shared with PostDetailViewController+OverflowMenu
    func sharePost() {
        let instanceActorId = viewModel.instanceActorId
        guard let url = LinkURL.forPost(
            instance: preferencesService.shareLinkInstance,
            originalPostUrl: viewModel.headerRow?.originalPostUrl,
            serverPostId: Int64(viewModel.serverPostId),
            instanceActorId: instanceActorId
        ) else {
            Haptics.warning()
            return
        }
        presentShareSheet(for: url, sourceItem: overflowBarButtonItem)
    }

    /// Presents the "Share as Image" editor for the current post. Mirrors
    /// ``sharePost()``'s permalink resolution (same warning-haptic bail when
    /// no URL can be formed, or the header row hasn't loaded) but hands the
    /// result to the share-as-image editor instead of the system share sheet.
    // internal: shared with PostDetailViewController+OverflowMenu
    func sharePostAsImage() {
        guard let headerRow = viewModel.headerRow else {
            Haptics.warning()
            return
        }
        let instanceActorId = viewModel.instanceActorId
        guard let url = LinkURL.forPost(
            instance: preferencesService.shareLinkInstance,
            originalPostUrl: headerRow.originalPostUrl,
            serverPostId: Int64(viewModel.serverPostId),
            instanceActorId: instanceActorId
        ) else {
            Haptics.warning()
            return
        }
        Haptics.tap()
        let sheet = ShareAsImageViewController.makeSheet(
            content: ShareCardContent(headerRow: headerRow, permalink: url),
            imageService: imageService,
            preferencesService: preferencesService
        )
        present(sheet, animated: true)
    }

    /// Shares the comment identified by `serverCommentId`. Prefers the
    /// comment's `ap_id` permalink; falls back to `<instance>/comment/<id>`.
    private func shareComment(serverCommentId: Int64) {
        let row = viewModel.commentRowsByElementId.values
            .first { $0.serverCommentId == serverCommentId }
        let instanceActorId = viewModel.instanceActorId
        guard let url = LinkURL.forComment(
            instance: preferencesService.shareLinkInstance,
            originalCommentUrl: row?.originalCommentUrl,
            serverCommentId: serverCommentId,
            instanceActorId: instanceActorId
        ) else {
            Haptics.warning()
            return
        }
        presentShareSheet(for: url)
    }

    /// Presents the "Share as Image" editor for the comment `serverCommentId`,
    /// with its ancestor chain up to the post root. Mirrors
    /// ``shareComment(serverCommentId:)``'s row lookup and permalink
    /// resolution. Filters "load more" placeholder rows
    /// (``PostDetailCommentRow/serverCommentId`` nil) out of the ancestor
    /// chain BEFORE handing it to the content builder — a placeholder carries
    /// no body/creator and must never render as a chain row.
    private func shareCommentAsImage(serverCommentId: Int64) {
        guard let row = viewModel.commentRowsByElementId.values
            .first(where: { $0.serverCommentId == serverCommentId })
        else {
            Haptics.warning()
            return
        }
        let instanceActorId = viewModel.instanceActorId
        guard let url = LinkURL.forComment(
            instance: preferencesService.shareLinkInstance,
            originalCommentUrl: row.originalCommentUrl,
            serverCommentId: serverCommentId,
            instanceActorId: instanceActorId
        ) else {
            Haptics.warning()
            return
        }
        let ancestors = ShareCardAncestry.ancestors(of: row.id, in: viewModel.orderedComments)
            .filter { $0.serverCommentId != nil }
        Haptics.tap()
        let sheet = ShareAsImageViewController.makeSheet(
            content: ShareCardContent(
                comment: row,
                ancestors: ancestors,
                header: viewModel.headerRow,
                permalink: url
            ),
            imageService: imageService,
            preferencesService: preferencesService
        )
        present(sheet, animated: true)
    }

    /// Routes a tapped body-text link. Thin wrapper over the shared
    /// ``InternalLinkRouting`` dispatch so every existing caller (long-press
    /// sheets, context menus, comment cells) keeps working unchanged.
    private func linkTapped(_ url: URL) {
        routeInternalLink(url)
    }

    /// Opens a tapped cross-post by its `ap_id`, via the same internal-link
    /// routing every other post-detail link uses (`.objectAtURL` federated
    /// resolve, then `routeToPost` -> `openPost`). Works for a cross-post on any
    /// instance, not just the current account's, and pushes on iPhone / opens
    /// in the detail column on iPad like every other in-app post navigation.
    private func openCrossPost(_ summary: CrossPostSummary) {
        guard let apURL = URL(string: summary.apId) else {
            logger.error("Cross-post tapped with an unparsable ap_id: \(summary.apId, privacy: .public)")
            return
        }
        routeInternalLink(URL.SpudInternalLink.objectAtURL(url: apURL).url)
    }

    private func pushPerson(personId: Lemmy.PersonID, instance: InstanceActorId) {
        let vc = PersonOrLoadingViewController(
            personId: personId,
            instance: instance,
            accountKeychainId: viewModel.accountKeychainId,
            dependencies: dependencies.nested
        )
        navigationController?.pushViewController(vc, animated: true)
    }

    private func pushCommunity(name: String, instance: InstanceActorId) {
        let vc = CommunityOrLoadingViewController(
            communityName: name,
            instance: instance,
            accountKeychainId: viewModel.accountKeychainId,
            dependencies: dependencies.nested
        )
        navigationController?.pushViewController(vc, animated: true)
    }

    /// Opens a post by its id valid for the current account, via the window's
    /// display entry (consistent with `AppCoordinator.open`).
    private func openPost(postId: Lemmy.PostID, instance _: InstanceActorId) {
        guard let window = view.window as? MainWindow else {
            logger.error("No MainWindow available to display post")
            return
        }
        window.display(serverPostId: postId, accountKeychainId: viewModel.accountKeychainId)
    }

    /// Opens the in-app instance screen for an instance; known hosts resolve
    /// from the Explorer directory, unknown but Lemmy-API-compatible hosts via a
    /// live probe, and anything else falls back to the browser.
    private func openInstance(_ instance: InstanceActorId) {
        InstanceRouter.openInstance(
            host: instance.host,
            from: self,
            accountKeychainId: viewModel.accountKeychainId,
            dependencies: dependencies.nested
        )
    }

    /// The original external-link behavior: image/video viewers or the browser.
    private func openExternal(_ url: URL) {
        let contentType = postContentDetector.contentTypeForUrl(
            url: url,
            thumbnailUrl: nil,
            embedTitle: nil,
            embedDescription: nil
        )
        switch contentType {
        case let .image(image):
            presentMediaViewer(imageUrl: image.imageUrl, thumbnailUrl: image.thumbnailUrl, preloadedImage: nil)
        case let .video(video):
            Task { await self.playVideo(url: video.videoUrl, appService: self.appService) }
        case .externalLink, .textOrEmpty:
            Task { await appService.open(url: url, on: self) }
        }
    }

    /// Long-press escape hatch for a body-text link: open in Spud, or for a web
    /// URL also open in the browser / copy / share. Internal-scheme links (e.g.
    /// mentions) are not browsable, so they offer in-app open only.
    private func linkLongPressed(_ url: URL) {
        // Internal-scheme links (e.g. mentions) have an opaque `info.ddenis.spud://`
        // URL that means nothing to the user, so show no title for them; web URLs
        // show the actual destination.
        let title: String? = url.spud == nil ? url.absoluteString : nil
        let sheet = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)

        if url.spud != nil {
            // Already an internal-scheme link (e.g. a mention) — only in-app open is meaningful.
            sheet.addAction(UIAlertAction(title: NSLocalizedString("Open in Spud", comment: ""), style: .default) { [weak self] _ in
                self?.linkTapped(url)
            })
        } else {
            // A web URL (external, or a Lemmy web link). Offer in-app open when it
            // classifies as Lemmy content, plus the browser / copy / share hatch.
            let isKnown: (String) -> Bool = { [viewModel] host in
                viewModel.isKnownInstance(host: host)
            }
            if let internalLink = LemmyURLParser.classify(url: url, isKnownInstance: isKnown) {
                sheet.addAction(UIAlertAction(title: NSLocalizedString("Open in Spud", comment: ""), style: .default) { [weak self] _ in
                    self?.linkTapped(internalLink.url)
                })
            }
            sheet.addAction(UIAlertAction(title: NSLocalizedString("Open in Browser", comment: ""), style: .default) { [weak self] _ in
                guard let self else { return }
                Task { await self.appService.open(url: url, on: self) }
            })
            sheet.addAction(UIAlertAction(title: NSLocalizedString("Copy Link", comment: ""), style: .default) { _ in
                UIPasteboard.general.url = url
            })
            sheet.addAction(UIAlertAction(title: NSLocalizedString("Share", comment: ""), style: .default) { [weak self] _ in
                self?.presentShareSheet(for: url)
            })
        }

        sheet.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))

        // iPad: anchor the popover to avoid a regular-width crash.
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        present(sheet, animated: true)
    }

    private func linkTappedFromPreview(_ safariVC: SFSafariViewController) {
        present(safariVC, animated: true)
    }

    /// The modern context menu for a long press on a comment's link preview card.
    /// Mirrors ``linkLongPressed(_:)``'s actions: a web URL gets a Safari peek plus
    /// open-in-Spud (when it classifies as Lemmy content) / open-in-browser / copy
    /// / share; an internal-scheme link (e.g. a community / mention) offers in-app
    /// open only, with NO preview (a non-`http(s)` scheme traps the Safari peek).
    private func linkContextMenuConfiguration(for url: URL) -> UIContextMenuConfiguration? {
        let menu = bodyLinkMenu(for: url)

        switch BodyLinkPreviewability.classify(url) {
        case .notPreviewable:
            // Internal / non-web link: in-app open only, nothing to peek.
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in menu }
        case .previewable:
            // A web URL: Safari peek plus the browser / copy / share hatch.
            return UIContextMenuConfiguration(
                identifier: nil,
                previewProvider: { [appService] in appService.safariViewControllerForPreview(url: url) },
                actionProvider: { _ in menu }
            )
        }
    }

    /// The context menu for a long-press on an INLINE body link (rendered by
    /// `SpudMarkdownKit`), shared with the card path via ``bodyLinkMenu(for:)``.
    ///
    /// The critical safety invariant: a preview is attached ONLY for a genuine
    /// `http(s)` web URL. An internal link (a `spud-markdown://` mention/community
    /// or the app scheme) or any other non-`http(s)` URL gets a preview-FREE
    /// configuration — the system link preview traps on a non-`http(s)` scheme,
    /// which is exactly the mention long-press crash.
    func inlineBodyLinkMenuConfiguration(for url: URL) -> UITextItem.MenuConfiguration? {
        let menu = bodyLinkMenu(for: url)

        switch BodyLinkPreviewability.classify(url) {
        case .previewable:
            // `init(menu:)` attaches the default system link preview (safe for http).
            return UITextItem.MenuConfiguration(menu: menu)
        case .notPreviewable:
            // No preview — never let UIKit build a link preview for this scheme.
            return UITextItem.MenuConfiguration(preview: nil, menu: menu)
        }
    }

    /// The actions offered for a long-press on a body link, shared by the inline
    /// text path (``inlineBodyLinkMenuConfiguration(for:)``) and the link-preview
    /// card path (``linkContextMenuConfiguration(for:)``) so both label and
    /// classify identically.
    ///
    /// An internal link — the app's own `info.ddenis.spud://` scheme OR a
    /// `SpudMarkdownKit` `spud-markdown://` mention/community/object link —
    /// collapses to a single "Open in Spud" action (opening its resolved in-app
    /// target). A web URL gets "Open in Spud" (only when it classifies as Lemmy
    /// content) plus Open in Browser / Copy Link / Share.
    private func bodyLinkMenu(for url: URL) -> UIMenu {
        let openInSpud = NSLocalizedString("Open in Spud", comment: "")

        if let internalURL = internalLinkTarget(for: url) {
            return UIMenu(children: [
                UIAction(title: openInSpud, image: UIImage(systemName: "arrow.up.forward.app")) { [weak self] _ in
                    self?.linkTapped(internalURL)
                },
            ])
        }

        var children: [UIMenuElement] = []
        let isKnown: (String) -> Bool = { [viewModel] host in
            viewModel.isKnownInstance(host: host)
        }
        if let internalLink = LemmyURLParser.classify(url: url, isKnownInstance: isKnown) {
            children.append(UIAction(title: openInSpud, image: UIImage(systemName: "arrow.up.forward.app")) { [weak self] _ in
                self?.linkTapped(internalLink.url)
            })
        }
        children.append(UIAction(
            title: NSLocalizedString("Open in Browser", comment: ""),
            image: UIImage(systemName: "safari")
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.appService.open(url: url, on: self) }
        })
        children.append(UIAction(
            title: NSLocalizedString("Copy Link", comment: ""),
            image: UIImage(systemName: "doc.on.doc")
        ) { _ in
            UIPasteboard.general.url = url
        })
        children.append(UIAction(
            title: NSLocalizedString("Share", comment: ""),
            image: UIImage(systemName: "square.and.arrow.up")
        ) { [weak self] _ in
            self?.presentShareSheet(for: url)
        })
        return UIMenu(children: children)
    }

    /// The in-app URL a body link should open, or `nil` if it is not an internal
    /// link. Covers both the app's own `info.ddenis.spud://` scheme (`url.spud`)
    /// and the `SpudMarkdownKit` `spud-markdown://` mention/community/object links.
    private func internalLinkTarget(for url: URL) -> URL? {
        if url.spud != nil { return url }
        return MarkdownInternalLink.resolve(url)
    }

    /// Commits a comment link preview's peek: opens the previewed Safari view
    /// controller, matching the post header's link preview.
    private func commitLinkPreviewContextMenu(
        _: UIContextMenuConfiguration,
        _ animator: UIContextMenuInteractionCommitAnimating
    ) {
        guard let safariVC = animator.previewViewController as? SFSafariViewController else { return }
        animator.addCompletion { [weak self] in
            self?.linkTappedFromPreview(safariVC)
        }
    }

    /// Thin forwarder so existing call sites stay unchanged; the logic lives in
    /// `UIViewController+MediaViewer.swift`.
    private func presentMediaViewer(
        imageUrl: URL,
        thumbnailUrl: URL?,
        preloadedImage: UIImage?,
        altText: String? = nil
    ) {
        presentMediaViewer(
            imageUrl: imageUrl,
            thumbnailUrl: thumbnailUrl,
            preloadedImage: preloadedImage,
            altText: altText,
            // All media opened from this post (header, body, or comment images)
            // inherits the post's NSFW state for the privacy screen.
            isNsfw: viewModel.headerRow?.isNsfw ?? false,
            dependencies: dependencies.own
        )
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
        guard !viewModel.accountScope.isSignedOut else {
            presentSignInGate(
                title: NSLocalizedString("Sign in to vote", comment: "Sign-in gate title when a signed-out user tries to vote")
            )
            return
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        // The optimistic write applied synchronously inside `vote`; reassure the
        // user it will be sent once they're back online.
        showOfflineActionToastIfNeeded(message: Self.offlineVoteToast)
        do {
            try await viewModel.voteOnComment(serverCommentId: serverCommentId, action: action)
        } catch {
            // The optimistic write already applied synchronously inside enqueue;
            // network failures are retried by the outbox and surfaced via toast.
            // This catch is now a defensive log only.
            alertService.handle(error, for: .vote)
        }
    }

    private func toggleSavedOnComment(serverCommentId: Int64) {
        guard canSaveOrPresentSignInAlert() else { return }
        let row = viewModel.commentRowsByElementId.values
            .first { $0.serverCommentId == serverCommentId }
        let currentlySaved = (row?.isSaved ?? false) == true
        Task { await setSavedOnComment(serverCommentId: serverCommentId, saved: !currentlySaved) }
    }

    private func setSavedOnComment(serverCommentId: Int64, saved: Bool) async {
        Haptics.tap()
        // The optimistic write applied synchronously inside `setSaved`; reassure
        // the user it will be sent once they're back online.
        showOfflineActionToastIfNeeded(message: Self.offlineSaveToast)
        do {
            try await viewModel.setSavedOnComment(serverCommentId: serverCommentId, saved: saved)
        } catch {
            alertService.handle(error, for: .save)
        }
    }

    // MARK: - Composing

    /// Reply to the post itself (a top-level comment).
    // internal: shared with PostDetailViewController+OverflowMenu
    func replyToPost() {
        presentComposer(target: .postReply(serverPostId: viewModel.serverPostId))
    }

    /// Reply to the comment identified by `serverCommentId`.
    private func replyToComment(serverCommentId: Int64) {
        presentComposer(target: .commentReply(
            serverPostId: viewModel.serverPostId,
            parentCommentId: Lemmy.CommentID(serverCommentId)
        ))
    }

    /// Presents the composer sheet for `target`, gating on sign-in: a
    /// signed-out account gets a "sign in to comment" alert instead. `initialBody`
    /// seeds the editor when no saved draft exists (used by the failed-comment
    /// Edit flow to preserve the user's text).
    // internal: shared with PostDetailViewController+DeleteRestore / +PendingComments
    func presentComposer(target: ComposerTarget, initialBody: String? = nil) {
        let keychainId = viewModel.accountKeychainId
        guard !viewModel.accountScope.isSignedOut else {
            presentSignInGate(
                title: NSLocalizedString("Sign in to comment", comment: "Sign-in gate title when a signed-out user tries to comment")
            )
            return
        }

        // Locked-post safety net. Every reply affordance (overflow "Add
        // comment", comment swipe/context-menu Reply) already omits itself
        // when the post is locked, so this is the backstop for any caller that
        // reaches the composer anyway. Gate only a BRAND-NEW top-level or
        // comment reply: `initialBody == nil` distinguishes that from
        // `editFailedComment`'s reopening of previously-typed, still-unsent
        // text (same `.postReply`/`.commentReply` cases, seeded with
        // `initialBody`) — that path isn't creating a new server-side comment
        // yet, just letting the user massage or discard their draft, so it
        // stays open. `.editComment` (editing an existing SENT comment) is
        // never gated here — the server allows editing on a locked post.
        let isNewReplyTarget: Bool
        switch target {
        case .postReply, .commentReply: isNewReplyTarget = true
        case .privateMessage, .newPost, .editComment: isNewReplyTarget = false
        }
        if
            isNewReplyTarget, initialBody == nil,
            !CommentLockPolicy.canComment(isPostLocked: viewModel.headerRow?.isLocked ?? false)
        {
            presentCommentLockedGate()
            return
        }

        // Presenting the composer is the user's intent to compose on this post.
        // Start listening for the composer-success signal now (idempotent), before
        // the send can complete, so a successfully-sent comment triggers the
        // comment-tree re-fetch that makes it visible (the success mirror writes no
        // `commentElement` row). Deliberately here — not in the view model's
        // observation bring-up — so merely viewing a post never resolves (and thus
        // starts/drains) the account's composer outbox.
        viewModel.beginComposerSuccessObservationIfNeeded()

        let composer = ComposerViewController.makeSheet(
            target: target,
            accountKeychainId: keychainId,
            initialBody: initialBody,
            dependencies: dependencies.own
        )
        present(composer, animated: true)
    }

    /// Presents the new-post composer in EDIT mode, seeded with the current post's
    /// title/body/url/nsfw and its (fixed) community. Sign-in gated, and only
    /// meaningful for the user's own, non-deleted post. The optimistic content
    /// write is applied at submit time, so the open header reflects the edit via
    /// its GRDB observation once the sheet dismisses.
    // internal: shared with PostDetailViewController+OverflowMenu
    func presentEditPost() {
        guard let row = viewModel.headerRow else { return }
        let keychainId = viewModel.accountKeychainId
        guard !viewModel.accountScope.isSignedOut else {
            presentSignInGate(
                title: NSLocalizedString("Sign in to edit", comment: "Sign-in gate title when a signed-out user tries to edit a post")
            )
            return
        }

        let composer = NewPostViewController.makeEditSheet(
            serverPostId: row.serverPostId,
            serverCommunityId: Lemmy.CommunityID(row.serverCommunityId),
            communityName: row.communityName,
            title: row.title,
            body: row.body,
            url: row.url,
            nsfw: row.isNsfw,
            accountKeychainId: keychainId,
            dependencies: dependencies.own
        )
        present(composer, animated: true)
    }

    /// Presents the new-post composer pre-filled with this post's title/url,
    /// plus a quoted-body attribution (the full post is loaded here, unlike
    /// the feed row), so the user can re-share it to another community. Sign-in
    /// gated, community picker left open for the user to choose the cross-post
    /// target. Uses the same durable-enqueue pending-post flow as the toolbar
    /// compose action.
    // internal: shared with PostDetailViewController+OverflowMenu
    func crossPostPost() {
        guard let row = viewModel.headerRow else { return }
        let keychainId = viewModel.accountKeychainId
        guard !viewModel.accountScope.isSignedOut else {
            presentSignInGate(
                title: NSLocalizedString("Sign in to post", comment: "Sign-in gate title when a signed-out user tries to cross-post")
            )
            return
        }

        let composer = NewPostViewController.makeCrossPostSheet(
            initialTitle: row.title,
            initialUrl: row.url,
            initialBody: crossPostBody(originalApId: row.originalPostUrl, originalBody: row.body),
            accountKeychainId: keychainId,
            dependencies: dependencies.own
        ) { [weak self] clientToken in
            guard let window = self?.view.window as? MainWindow else { return }
            window.displayPending(clientToken: clientToken, accountKeychainId: keychainId)
        }
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
        case newSinceBanner
        /// The "Cross-posted to N communities" section. A plain marker (no
        /// associated value, like `.commentsFailed`) — the cell provider reads
        /// `viewModel.crossPosts` when configuring the cell.
        case crossPostedTo
        case commentLoadingSkeleton
        case commentsEmpty
        /// The inline "couldn't load comments" failed-state row. A plain marker
        /// (no associated value) keeps `Item` trivially `Hashable`; the cell
        /// provider reads the classified failure from the view model when
        /// configuring the cell.
        case commentsFailed
        /// Terminal row shown when the comment listing stopped with pages still
        /// outstanding. Tapping it resumes the walk.
        case commentsLoadMore
        case comment(elementId: Int64)
    }

    private func setupDataSource() {
        let appearance = appearanceService
        let imageService = imageService
        let linkEmbedService = linkEmbedService
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
                if let row = self?.viewModel.headerRow, let self {
                    let viewModel = PostDetailHeaderViewModel(
                        row: row,
                        appearance: appearance,
                        postContentDetector: postContentDetector,
                        blurNsfw: preferencesService.blurNsfw,
                        isRevealed: headerNsfwRevealed,
                        fetchLinkEmbeds: preferencesService.fetchLinkEmbeds
                    )
                    cell.configure(with: viewModel, imageService: imageService, linkEmbedService: linkEmbedService)
                }
                cell.onRevealBlur = { [weak self] in
                    guard let self else { return }
                    headerNsfwRevealed = true
                    updateHeaderPrivacy()
                    var snapshot = dataSource.snapshot()
                    snapshot.reconfigureItems([.header])
                    dataSource.apply(snapshot, animatingDifferences: false)
                }
                cell.linkTapped = { [weak self] url in self?.linkTapped(url) }
                cell.linkLongPressed = { [weak self] url in self?.linkLongPressed(url) }
                cell.linkTappedFromPreview = { [weak self] safariVC in self?.linkTappedFromPreview(safariVC) }
                cell.imageTapped = { [weak self] imageUrl, thumbnailUrl, currentImage in
                    self?.presentMediaViewer(
                        imageUrl: imageUrl,
                        thumbnailUrl: thumbnailUrl,
                        preloadedImage: currentImage,
                        altText: self?.viewModel.headerRow?.altText
                    )
                }
                cell.videoTapped = { [weak self] videoUrl in
                    guard let self else { return }
                    Task { await self.playVideo(url: videoUrl, appService: self.appService) }
                }
                cell.openInBrowser = { [weak self] url in
                    guard let self else { return }
                    Task { await appService.open(url: url, on: self) }
                }
                cell.upvoteTapped = { [weak self] in
                    guard let self else { return }
                    Task { await self.vote(serverPostId: Int64(self.viewModel.serverPostId), action: .upvote) }
                }
                cell.downvoteTapped = { [weak self] in
                    guard let self else { return }
                    Task { await self.vote(serverPostId: Int64(self.viewModel.serverPostId), action: .downvote) }
                }
                cell.saveTapped = { [weak self] in
                    guard let self else { return }
                    toggleSaved(serverPostId: Int64(viewModel.serverPostId))
                }
                cell.onBodyLinkTapped = { [weak self] url in
                    self?.linkTapped(MarkdownInternalLink.resolve(url) ?? url)
                }
                cell.onBodyLinkMenu = { [weak self] url in
                    self?.inlineBodyLinkMenuConfiguration(for: url)
                }
                cell.onBodyImageTapped = { [weak self] url, altText, _ in
                    self?.presentMediaViewer(
                        imageUrl: url,
                        thumbnailUrl: nil,
                        preloadedImage: nil,
                        altText: altText
                    )
                }
                cell.onBodyVideoTapped = { [weak self] url in
                    self?.presentVideoPlayer(url: url)
                }
                // Audio reuses the video player, which handles audio-only URLs.
                cell.onBodyAudioTapped = { [weak self] url in
                    self?.presentVideoPlayer(url: url)
                }
                cell.isBeingConfigured = false
                return cell

            case .newSinceBanner:
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: PostDetailNewSinceBannerCell.reuseIdentifier,
                    for: indexPath
                ) as! PostDetailNewSinceBannerCell
                let accent = self?.tableView.tintColor ?? .systemTeal
                cell.configure(
                    count: self?.viewModel.newCommentCount ?? 0,
                    relativeText: self?.viewModel.previousVisitAt?.relativeString,
                    accent: accent
                )
                cell.jumpTapped = { [weak self] in self?.jumpToFirstNewComment() }
                return cell

            case .crossPostedTo:
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: PostDetailCrossPostsCell.reuseIdentifier,
                    for: indexPath
                ) as! PostDetailCrossPostsCell
                cell.configure(with: self?.viewModel.crossPosts ?? [])
                cell.crossPostTapped = { [weak self] summary in self?.openCrossPost(summary) }
                return cell

            case .commentLoadingSkeleton:
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: PostDetailCommentLoadingCell.reuseIdentifier,
                    for: indexPath
                ) as! PostDetailCommentLoadingCell
                cell.startAnimating()
                return cell

            case .commentsEmpty:
                return tableView.dequeueReusableCell(
                    withIdentifier: PostDetailEmptyCommentsCell.reuseIdentifier,
                    for: indexPath
                ) as! PostDetailEmptyCommentsCell

            case .commentsFailed:
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: PostDetailCommentsFailedCell.reuseIdentifier,
                    for: indexPath
                ) as! PostDetailCommentsFailedCell
                // The failed row is only ever in the snapshot when
                // `commentFetchError` is set, but fall back to a generic
                // unreachable failure if the cell is somehow dequeued without one.
                let failure = self?.viewModel.commentFetchError
                    ?? LoadFailure(kind: .unreachable, diagnostics: "")
                cell.configure(with: failure)
                cell.onRetry = { [weak self] in
                    Task { await self?.viewModel.fetchComments() }
                }
                return cell

            case .commentsLoadMore:
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: PostDetailLoadMoreCommentsCell.reuseIdentifier,
                    for: indexPath
                ) as! PostDetailLoadMoreCommentsCell
                cell.setLoading(self?.viewModel.isLoadingComments ?? false)
                return cell

            case let .comment(elementId):
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: PostDetailCommentCell.reuseIdentifier,
                    for: indexPath
                ) as! PostDetailCommentCell

                // A synthetic (negative) id is a pending overlay node, rendered
                // before the real-row lookup so it never trips the assertion below.
                if let pending = self?.pendingStateByElementId[elementId] {
                    cell.configurePending(pending, imageService: imageService)
                    cell.pendingTapped = { [weak self] in
                        self?.handlePendingTap(elementId: elementId)
                    }
                    return cell
                }

                guard var row = self?.viewModel.commentRowsByElementId[elementId] else {
                    logger.assertionFailure("Missing PostDetailCommentRow for element \(elementId)")
                    return cell
                }

                // Pending EDIT overlay: render the locally-edited body in place of
                // the server's, keeping the row's votes/score/badges. The status
                // line (Sending… / Failed) is applied after configure(with:).
                let editOverlay = self?.editOverlayByElementId[elementId]
                if let editOverlay {
                    row = Self.row(row, replacingBody: editOverlay.body)
                }

                let isCollapsed = self?.viewModel.isCollapsed(elementId: elementId) ?? false
                let collapsedCount = self?.collapsedDescendantCounts[elementId]
                let collapsedNewCount = self?.collapsedNewDescendantCounts[elementId]
                let isBlockedRevealed = self?.revealedBlockedElementIds.contains(elementId) ?? false
                let viewModel = PostDetailCommentViewModel(
                    row: row,
                    appearance: appearance,
                    postCreatorPersonId: self?.viewModel.headerRow?.creatorPersonId,
                    isCollapsed: isCollapsed,
                    collapsedDescendantCount: collapsedCount,
                    collapsedNewDescendantCount: collapsedNewCount,
                    isBlockedRevealed: isBlockedRevealed,
                    isNew: self?.viewModel.isNewComment(elementId: elementId) ?? false,
                    fetchLinkEmbeds: self?.preferencesService.fetchLinkEmbeds ?? false,
                    isLoadingMore: self?.viewModel.isLoadingMore(elementId: elementId) ?? false
                )
                cell.configure(with: viewModel, imageService: imageService, linkEmbedService: linkEmbedService)
                if let editOverlay {
                    cell.applyEditOverlayStatus(editOverlay)
                    cell.pendingTapped = { [weak self] in
                        self?.handleEditOverlayTap(elementId: elementId)
                    }
                }
                cell.linkTapped = { [weak self] url in self?.linkTapped(url) }
                cell.linkLongPressed = { [weak self] url in self?.linkLongPressed(url) }
                cell.linkPreviewContextMenu = { [weak self] url in self?.linkContextMenuConfiguration(for: url) }
                cell.linkPreviewContextMenuCommit = { [weak self] configuration, animator in
                    self?.commitLinkPreviewContextMenu(configuration, animator)
                }
                cell.onBodyImageLoaded = { [weak tableView] in
                    // An inline body image loaded; snap this row to its new height
                    // without animation (an animated re-measure zooms the image in
                    // from a corner — see the helper's doc).
                    tableView?.remeasureRowHeightsWithoutAnimation()
                }
                cell.onBodyLinkTapped = { [weak self] url in
                    self?.linkTapped(MarkdownInternalLink.resolve(url) ?? url)
                }
                cell.onBodyLinkMenu = { [weak self] url in
                    self?.inlineBodyLinkMenuConfiguration(for: url)
                }
                cell.onBodyImageTapped = { [weak self] url, altText, _ in
                    self?.presentMediaViewer(
                        imageUrl: url,
                        thumbnailUrl: nil,
                        preloadedImage: nil,
                        altText: altText
                    )
                }
                cell.onBodyVideoTapped = { [weak self] url in
                    self?.presentVideoPlayer(url: url)
                }
                cell.onBodyAudioTapped = { [weak self] url in
                    // Audio reuses the video player, which handles audio-only URLs.
                    self?.presentVideoPlayer(url: url)
                }
                cell.revealBlockedTapped = { [weak self] in
                    self?.revealBlocked(elementId: elementId)
                }
                // Tap-to-collapse is the primary collapse affordance (Apollo
                // parity); "load more" placeholders are not collapsible.
                cell.collapseTapped = { [weak self] in
                    self?.toggleCollapse(elementId: elementId)
                }
                cell.loadMoreTapped = { [weak self] in
                    self?.handleLoadMoreTap(elementId: elementId, parentServerId: row.moreParentId)
                }

                // Swipe slots are user-configurable (M8). Defaults reproduce the
                // prior vote / vote / reply / collapse layout. Collapse is also
                // available via tap; a collapse swipe slot mirrors it for
                // gesture-first users.
                // A "load more" placeholder has no backing comment, so it carries
                // no swipe actions — tapping the row is its only interaction.
                if row.moreChildCount != nil {
                    cell.swipeActionConfiguration = nil
                } else {
                    let general = appearance.general
                    // The reply swipe slot is HIDDEN (not merely disabled) on a
                    // locked post — see `CommentLockPolicy.sanitizedSwipeActionConfig`.
                    let isPostLocked = self?.viewModel.headerRow?.isLocked ?? false
                    let swipeConfig = CommentLockPolicy.sanitizedSwipeActionConfig(
                        self?.commentSwipeActionConfig ?? .defaultComments,
                        isPostLocked: isPostLocked
                    )
                    cell.swipeActionConfiguration = swipeConfig.viewConfiguration(
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
        scrollOdometer.update(
            offsetY: scrollView.contentOffset.y,
            contentHeight: scrollView.contentSize.height,
            viewportHeight: scrollView.bounds.height
        )
        reportScrollDistanceIfNeeded()

        updateJumpButtonVisibility()
    }

    /// Fun stats: reports accumulated scroll distance in batches (threshold
    /// 1000pt) so we don't spawn a `Task` per scroll tick. `force: true`
    /// flushes any sub-threshold remainder (e.g. on `viewWillDisappear`).
    private func reportScrollDistanceIfNeeded(force: Bool = false) {
        let points = scrollOdometer.take()
        guard points > 0, force || points >= 1000 else {
            // Under threshold: put it back rather than losing it.
            if points > 0 { scrollOdometer.credit(points) }
            return
        }
        FunStats.record(.scrollDistancePoints, amount: points)
    }

    /// Handles a tap on the terminal "Load more comments" row: the row has no
    /// nested button (see ``PostDetailLoadMoreCommentsCell``), so the tap is
    /// driven by ordinary table-row selection instead. Every other row keeps
    /// `selectionStyle = .none` and drives its own taps (gesture recognizers /
    /// buttons), so this is the sole consumer of row selection today.
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard dataSource.itemIdentifier(for: indexPath) == .commentsLoadMore else { return }
        tableView.deselectRow(at: indexPath, animated: true)
        Task { [weak self] in await self?.viewModel.loadMoreCommentPages() }
    }

    func tableView(
        _ tableView: UITableView,
        willDisplay cell: UITableViewCell,
        forRowAt indexPath: IndexPath
    ) {
        guard
            case let .comment(elementId) = dataSource.itemIdentifier(for: indexPath),
            let cell = cell as? PostDetailCommentCell
        else { return }
        let didAnimate = cell.startFreshWashIfNeeded(
            hasAnimated: animatedNewCommentIds.contains(elementId)
        )
        if didAnimate {
            animatedNewCommentIds.insert(elementId)
        }
        if permalinkHighlightElementIds.remove(elementId) != nil {
            cell.playPermalinkHighlight()
        }
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
            let commentRow = viewModel.commentRowsByElementId[elementId],
            let serverCommentId = commentRow.serverCommentId
        else { return nil }

        let isSaved = commentRow.isSaved ?? false
        let isOwnComment = isOwnContent(creatorPersonId: commentRow.creatorPersonId)
        let isDeleted = commentRow.isDeleted ?? false
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
                let shareAsImageAction = UIAction(
                    title: NSLocalizedString("Share as Image", comment: "Context-menu action to share a comment as a designed image card"),
                    image: UIImage(systemName: "photo")
                ) { [weak self] _ in
                    self?.shareCommentAsImage(serverCommentId: serverCommentId)
                }
                var children: [UIMenuElement] = [upvoteAction, downvoteAction]
                // Reply is OMITTED (not merely disabled) when the post is
                // locked — the server rejects new comments on a locked post.
                if CommentLockPolicy.canComment(isPostLocked: self?.viewModel.headerRow?.isLocked ?? false) {
                    children.append(replyAction)
                }
                children.append(contentsOf: [saveAction, shareAction, shareAsImageAction])
                // "Remind Me…" scoped to this comment's thread (Phase 3) -
                // mirrors the post overflow menu's placement (right after the
                // primary interaction actions, before ownership/moderation).
                // Omitted (not disabled) when the comment lacks a resolvable
                // server id or ap_id.
                if let remindMenu = self?.commentRemindMeMenu(for: commentRow) {
                    children.append(remindMenu)
                }
                if isOwnComment {
                    // Your own comment: offer Edit + Delete (or Restore if already
                    // deleted). Editing a deleted comment isn't offered. Delete is
                    // destructive and confirms first.
                    if isDeleted {
                        let restoreAction = UIAction(
                            title: NSLocalizedString("Restore", comment: "Context-menu action to restore the user's own deleted comment"),
                            image: UIImage(systemName: "arrow.uturn.backward")
                        ) { [weak self] _ in
                            self?.setDeletedOnComment(serverCommentId: serverCommentId, deleted: false)
                        }
                        children.append(restoreAction)
                    } else {
                        // Prefer an in-flight/failed edit's pending body so re-opening
                        // Edit shows the user's latest text, not the stale server body.
                        let currentBody = self?.editOverlayByElementId[commentRow.id]?.body ?? commentRow.body ?? ""
                        let editAction = UIAction(
                            title: NSLocalizedString("Edit", comment: "Context-menu action to edit the user's own comment"),
                            image: UIImage(systemName: "pencil")
                        ) { [weak self] _ in
                            self?.editOwnComment(serverCommentId: serverCommentId, currentBody: currentBody)
                        }
                        children.append(editAction)
                        let deleteAction = UIAction(
                            title: NSLocalizedString("Delete", comment: "Context-menu action to delete the user's own comment"),
                            image: UIImage(systemName: "trash"),
                            attributes: .destructive
                        ) { [weak self] _ in
                            self?.promptDeleteComment(serverCommentId: serverCommentId)
                        }
                        children.append(deleteAction)
                    }
                } else {
                    // Reporting your own comment is meaningless, so only offer it
                    // on other people's content.
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
        let isOwnPost = isOwnContent(creatorPersonId: viewModel.headerRow?.creatorPersonId)
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
                let shareAsImageAction = UIAction(
                    title: NSLocalizedString("Share as Image", comment: "Context-menu action to share a post as a designed image card"),
                    image: UIImage(systemName: "photo")
                ) { [weak self] _ in
                    self?.sharePostAsImage()
                }
                var children: [UIMenuElement] = [shareAction, shareAsImageAction]
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
                if isOwnPost {
                    let currentlyDeleted = self?.viewModel.headerRow?.isDeleted ?? false
                    // Editing a deleted post isn't offered (restore it first).
                    if !currentlyDeleted {
                        let editAction = UIAction(
                            title: NSLocalizedString("Edit", comment: "Context-menu action to edit the user's own post"),
                            image: UIImage(systemName: "pencil")
                        ) { [weak self] _ in
                            self?.presentEditPost()
                        }
                        children.append(editAction)
                    }
                    let deleteAction = UIAction(
                        title: currentlyDeleted
                            ? NSLocalizedString("Restore", comment: "Context-menu action to restore the user's own deleted post")
                            : NSLocalizedString("Delete", comment: "Context-menu action to delete the user's own post"),
                        image: UIImage(systemName: currentlyDeleted ? "arrow.uturn.backward" : "trash"),
                        attributes: currentlyDeleted ? [] : .destructive
                    ) { [weak self] _ in
                        guard let self else { return }
                        if currentlyDeleted {
                            setDeletedOnPost(serverPostId: viewModel.serverPostId, deleted: false)
                        } else {
                            promptDeletePost(serverPostId: viewModel.serverPostId)
                        }
                    }
                    children.append(deleteAction)
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

// MARK: - InternalLinkRouting

extension PostDetailViewController: InternalLinkRouting {
    var linkRouterAppDatabase: AppDatabase {
        appDatabase
    }

    /// Documented exception: this is the sole intended `lemmyService` reference
    /// left at the PostDetail VC layer (`grep lemmyService PostDetailViewController*.swift`
    /// matches only here) — the shared `InternalLinkRouting` machinery is written
    /// against the raw `LemmyServiceType`, not the scene-owned `PostDetailLemmyServicing`
    /// seam, so it needs the account's actual service handed through as-is. Every
    /// other PostDetail mutation dispatches through `PostDetailViewModel` instead.
    var linkRouterLemmyService: LemmyServiceType {
        viewModel.accountScope.lemmyService
    }

    func routeToPerson(personId: Lemmy.PersonID, instance: InstanceActorId) {
        pushPerson(personId: personId, instance: instance)
    }

    func routeToCommunity(name: String, instance: InstanceActorId) {
        pushCommunity(name: name, instance: instance)
    }

    func routeToPost(postId: Lemmy.PostID, instance: InstanceActorId) {
        openPost(postId: postId, instance: instance)
    }

    func routeToInstance(_ instance: InstanceActorId) {
        openInstance(instance)
    }

    /// Keeps PostDetail's richer external handling (media-type detection via
    /// `postContentDetector`) as the routed external behavior.
    func routeToExternal(_ url: URL) {
        openExternal(url)
    }
}
