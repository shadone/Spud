//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import Observation
import OSLog
import SpudDataKit
import SpudUIKit
import SpudUtilKit
import SwiftUI
import UIKit

private let logger = Logger.app

class PostListViewController: UIViewController {
    typealias OwnDependencies =
        HasAccountService &
        HasAlertService &
        HasAppDatabase &
        HasAppService &
        HasAppearanceService &
        HasDiagnosticLog &
        HasImageService &
        HasPostContentDetectorService &
        HasPreferencesService &
        HasReachabilityMonitor
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

    var appService: AppServiceType {
        dependencies.own.appService
    }

    var diagnosticLog: DiagnosticLogging {
        dependencies.own.diagnosticLog
    }

    var imageService: ImageServiceType {
        dependencies.own.imageService
    }

    var preferencesService: PreferencesServiceType {
        dependencies.own.preferencesService
    }

    /// `internal` (not `private`) ONLY so the offline-download extension
    /// (`PostListViewController+OfflineDownload.swift`) can read it for its
    /// offline pre-check. Not public API — treat as private to this file's
    /// own use plus that one extension seam.
    var reachabilityMonitor: ReachabilityMonitoring {
        dependencies.own.reachabilityMonitor
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
        tableView.register(PaginationErrorFooterCell.self, forCellReuseIdentifier: PaginationErrorFooterCell.reuseIdentifier)

        return tableView
    }()

    private lazy var refreshControl: UIRefreshControl = {
        let control = UIRefreshControl()
        control.addTarget(self, action: #selector(refreshTriggered), for: .valueChanged)
        return control
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
        case paginationRetry
    }

    private var dataSource: UITableViewDiffableDataSource<Section, Item>!

    // MARK: Private

    private var seenDwellTracker = SeenDwellTracker(threshold: 0.5)
    private var seenFlushTimer: Timer?

    /// Undo state for an accidental status-bar scroll-to-top. See
    /// `ScrollToTopUndo`; wired in the `UITableViewDelegate` extension below.
    private var scrollUndo = ScrollToTopUndo()

    /// The rows actually rendered, after the hide-read filter. Drives the empty
    /// state so an all-read feed shows the designed empty state when hiding. The
    /// full ordered snapshot + the `serverPostId` lookup live on the view model
    /// (`orderedRows` / `row(forServerPostId:)`); this is the VC-side hide-read
    /// view transform of them.
    private var displayedRows: [PostListRow] = []
    /// Primary `serverPostId` -> its collapsed cross-post siblings, recomputed by
    /// `CrossPostGrouper` on every `apply(rows:)` (empty when grouping is off).
    /// Read by the cell provider (the "Also in N communities" affordance) and the
    /// context menu (the "Also posted in" jump submenu). Not part of the
    /// diffable snapshot's identity — `displayedRows` / `viewModel.orderedRows`
    /// stay the source of truth for what's on screen; this is auxiliary lookup
    /// state for rows already in `displayedRows`.
    private var crossPostSiblings: [Int64: [PostListRow]] = [:]
    /// The backing account's moderation capability, refreshed when the feed
    /// loads. Drives whether the post context menu shows mod actions. `.none`
    /// until the first fetch (and for signed-out accounts).
    private var moderationCapability: ModerationCapability = .none
    /// Set once this controller has processed its first row reaction for the
    /// current feed, so the pinned-read set is seeded from the view model's
    /// first-snapshot capture exactly once (subsequent hide-read toggles re-pin
    /// explicitly). Reset on every `feedChanged`.
    private var hasSeededPinnedReadIds = false
    /// The view model's `rowsRevision` captured at the most recent `feedChanged`,
    /// alongside the `hasSeededPinnedReadIds` reset. The rows reaction is a
    /// persistent loop (it is NOT recreated on a feed switch), so a revision
    /// delivery enqueued from the PRE-restart observation can arrive AFTER
    /// `feedChanged` resets the seeding latch; applying it would seed
    /// `pinnedReadIds` from the just-reset-empty `firstSnapshotReadIds` and latch,
    /// so the new feed's real first emit never seeds — hide-read pinning stays
    /// broken for the whole feed session. The reaction skips any delivery whose
    /// revision is `<= ` this, so only the NEW observation's emits (revision
    /// strictly greater — `rowsRevision` is monotonic and never reset) seed and
    /// render. Restores the base's stale-emits-never-apply semantics.
    private var rowsRevisionAtRestart = 0
    /// Reacts to the view model's `rowsRevision` DB-emit signal, running the
    /// per-emit render pipeline (see `startRowsReaction`).
    private var rowsObservationTask: Task<Void, Never>?
    private var titleObservationTask: Task<Void, Never>?
    private var loadStateObservationTask: Task<Void, Never>?
    private var paginationStateObservationTask: Task<Void, Never>?
    private var reachabilityObservationTask: Task<Void, Never>?
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

    /// Cross-post grouping preference, seeded from `PreferencesService` and kept
    /// live. Changes re-apply the current snapshot through `CrossPostGrouper`.
    private var groupCrossPosts = true

    /// Mark-read prefs, seeded and kept live. Drive `scrollViewDidScroll`'s
    /// best-effort mark-as-read.
    private var markPostsRead = true
    private var markPostsReadOnScroll = false

    /// For `HideReadPostsFilter.Mode.onRefresh`: the server post ids that were
    /// already read when the current feed view began, captured on the first
    /// snapshot. Only these are hidden, so posts read mid-session don't vanish
    /// from under the user until the next refresh.
    private var pinnedReadIds: Set<Int64> = []

    /// Posts whose NSFW media the user revealed this session (by server post id).
    /// Not persisted; resets on relaunch.
    private var revealedNsfwPostIds: Set<Int64> = []

    /// Server post ids of revealed-NSFW thumbnails currently on screen. Drives the
    /// feed's privacy registration so a revealed NSFW thumbnail is hidden from the
    /// app-switcher snapshot / screen capture (see PrivacyScreen).
    private var visibleRevealedNsfwPostIds: Set<Int64> = []
    /// Whether the feed is currently on-screen; gates the privacy registration so a
    /// revealed thumbnail under a pushed detail screen doesn't keep covering.
    private var isViewVisible = false
    private let feedSensitiveToken = SensitiveContentToken()

    /// Server post ids already enqueued for a background mark-as-read (scroll-out
    /// or media-open), so we don't fire the API repeatedly for the same row.
    private var markedReadIds: Set<Int64> = []

    var sortTypeBarButtonItem: UIBarButtonItem!
    var sortTypeMenuActionsBySortType: [Lemmy.SortType: UIAction] = [:]

    /// The sort-order pull-down menu bar button. Exposed so a host that owns the
    /// navigation bar (e.g. CommunityViewController, which embeds this controller)
    /// can surface the feed's sort control in its own navbar. Non-nil once the
    /// controller is initialized: `setupSortTypeMenu()` runs in `setup()` from
    /// `init`, before the view loads.
    var feedSortMenuBarButtonItem: UIBarButtonItem {
        sortTypeBarButtonItem
    }

    var quickSwitchBarButtonItem: UIBarButtonItem!

    /// Keeps the Quick Switch popover a popover (not a sheet) on iPhone. The
    /// popover holds this only weakly, so the controller retains it.
    private let forcePopoverDelegate = ForcePopoverDelegate()

    /// Whether this feed is the Posts-tab primary feed that sits atop the feed
    /// switcher in the navigation stack. Currently inert (compose moved to the
    /// trailing nav-bar slot, so it no longer affects the back button); retained
    /// as the primary-feed marker for the forthcoming feed-title redesign.
    private let showsQuickSwitch: Bool

    // MARK: Offline download

    // The members in this section (`offlineDownloadService`, `offlineDownloadTask`,
    // `offlineDownloadProgressViewModel`, and the `currentFeedHandle` /
    // `currentAccountScope` / `currentAccountKeychainId` accessors over the
    // `private` view model) are `internal` ONLY so the offline-download extension
    // (`PostListViewController+OfflineDownload.swift`) can drive the launch +
    // lifecycle. They are an extension seam, not public API.

    /// The engine that predownloads the current feed for offline browsing.
    /// Instantiated lazily (and held for the controller's lifetime) so a download
    /// started from the short-lived Quick Switch popover outlives that popover —
    /// the actor guarantees only one download runs at a time across taps. Built
    /// directly here (rather than via the DI container) because it needs only the
    /// two services the controller already holds, and no other screen launches
    /// downloads.
    ///
    /// The web-archive pair (`WebArchiveCapturer` + `OfflineWebArchiveStore`) is
    /// wired in only when the store can be opened (the App Group container is
    /// reachable) — the capturer is `@MainActor`, constructed on the app side.
    /// When the store can't open, the "Also save linked web pages" toggle simply
    /// no-ops on the data side (the toggle stays usable; capture is skipped).
    lazy var offlineDownloadService = OfflineDownloadService(
        appDatabase: appDatabase,
        imageService: imageService,
        diagnostics: diagnosticLog,
        webArchiveCapturer: WebArchiveCapturer(),
        webArchiveStore: try? OfflineWebArchiveStore(appDatabase: appDatabase)
    )

    /// The task draining the in-flight download's progress stream, updating the
    /// status pill's view model on each value. Retained so the controller can tear
    /// it down (the pill's ✕ or `deinit`). Cancelling this task terminates the
    /// stream, which cancels the download via the stream's `onTermination`.
    var offlineDownloadTask: Task<Void, Never>?

    /// The status pill's view model, held so stream values can push updates into
    /// it. Non-nil exactly while this controller owns a live download; nil
    /// otherwise. `deinit` uses this to tell whether it should remove the pill it
    /// showed (so it never removes a pill another feed's controller owns).
    var offlineDownloadProgressViewModel: OfflineDownloadProgressViewModel?

    /// The feed currently shown, for the offline-download launch path (the
    /// view model is `private`).
    var currentFeedHandle: FeedHandle {
        viewModel.feed
    }

    /// The backing account scope, for the offline-download launch path.
    var currentAccountScope: AccountScope {
        viewModel.accountScope
    }

    /// The backing account's durable keychain id, for the offline-download
    /// launch path.
    var currentAccountKeychainId: String {
        viewModel.accountKeychainId
    }

    /// The backing account's `(accountId, siteId)` local row ids, for the
    /// offline-download launch path (the view model is `private`). nil until the
    /// account is imported.
    var currentAccountAndSiteRowIds: (accountId: Int64, siteId: Int64)? {
        viewModel.accountAndSiteRowIds()
    }

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
            accountScope: dependencies.accountService.scope(forAccountKeychainId: accountKeychainId),
            appDatabase: dependencies.appDatabase,
            dependencies: dependencies
        )

        super.init(nibName: nil, bundle: nil)

        swipeActionConfig = dependencies.preferencesService
            .postSwipeActions
            .sanitized(for: .post)

        hideReadPosts = dependencies.preferencesService.hideReadPosts
        hideReadPostsMode = dependencies.preferencesService.hideReadPostsMode
        groupCrossPosts = dependencies.preferencesService.groupCrossPostsInFeed
        markPostsRead = dependencies.preferencesService.markPostsRead
        markPostsReadOnScroll = dependencies.preferencesService.markPostsReadOnScroll

        setup()
        configureTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// `isolated deinit` so the body runs on the main actor: `stopObservations()`
    /// is main-actor isolated, and a live observation task can outlive the
    /// controller (it strong-holds the view model), so this must be able to reach
    /// the view model to cancel it.
    isolated deinit {
        rowsObservationTask?.cancel()
        titleObservationTask?.cancel()
        loadStateObservationTask?.cancel()
        paginationStateObservationTask?.cancel()
        reachabilityObservationTask?.cancel()
        swipeActionsObservationTask?.cancel()
        offlineDownloadTask?.cancel()
        // Cancelling the drain task above tears down the run; if this controller
        // still owned a live download, remove the window-anchored pill it showed
        // so it can't linger without a drain updating it. (Scoped by the non-nil
        // view model so we never remove a pill another feed's controller owns.)
        // NOTE (robustness follow-up): because ownership lives on this VC, a
        // Posts-tab VC dealloc under memory pressure cancels the download too;
        // moving ownership to an app-lifetime object would let the run + pill
        // outlive the controller. Deferred.
        if offlineDownloadProgressViewModel != nil {
            OfflineDownloadStatusPresenter.shared.dismiss(animated: false)
        }
        for task in displayPrefsObservationTasks {
            task.cancel()
        }
        // Proactively tear down the view model's row observation so it doesn't
        // outlive the controller. (The view model's `deinit` also cancels it,
        // but that only runs once no live observation task is still
        // strong-holding the view model — which the row observation's
        // `guard let self` + unending `for await` otherwise would, forever.)
        viewModel.stopObservations()
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
        setupQuickSwitchButton()
        updateTrailingBarButtonItems()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // The table width is only known after layout; (re)size the scrolling
        // header to it. Guarded against no-op churn, so this is cheap to call
        // every pass and handles rotation / width changes for free.
        layoutScrollingHeaderIfNeeded()
        // A split collapse/expand changes the primary column's width (and thus
        // whether the feed-name title control should be the tappable popover anchor
        // or a plain title) but does NOT change this controller's own size class,
        // so re-evaluate here, where `splitViewController?.isCollapsed` is accurate.
        refreshTitleControlModeIfNeeded()
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
        // `layoutScrollingHeaderIfNeeded` bails before it can sync the insets when
        // the table has no width yet — the exact community cold-open order, where
        // this host installs its header AFTER the embedded feed's `viewDidLoad`
        // already showed the loading skeleton (inset 0, no header then). Sync the
        // background-surface insets directly too, so a skeleton / state surface
        // already sitting in the shared `backgroundView` slot re-insets below the
        // just-installed header immediately, instead of staying pinned at inset 0
        // behind it (hidden in the below-header region) until a later layout pass.
        syncSkeletonHeaderInset()
        syncStateSurfaceHeaderInset()
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

        // Commit a changed header height — reassigning `tableHeaderView` is what
        // makes the table adopt it — but guard the reassignment so an unchanged
        // height skips the churn (this runs every layout pass).
        if abs(header.frame.height - height) > 0.5 {
            header.frame.size.height = height
            tableView.tableHeaderView = header
        }

        // Keep the loading skeleton AND the empty/error state surface clear of the
        // header on EVERY pass — NOT only when the height changed. Both share the
        // table's `backgroundView` slot and are inset below the header; a surface
        // can be installed AFTER the header already settled at its final height
        // (the skeleton shows on a reload while the community header is measured,
        // or a host installs a pre-sized header), in which case the change-guard
        // above never fires and the surface would otherwise stay pinned at inset 0
        // behind the opaque header — the blank below-header region this guards
        // against. Reads the freshly committed header frame height. Cheap: each
        // sync only reassigns a constraint constant when it actually changed.
        syncSkeletonHeaderInset()
        syncStateSurfaceHeaderInset()
    }

    /// Installs the trailing nav-bar buttons. The sort menu is always present; on
    /// the standalone frontpage feed a compose ("New post") button sits as the
    /// right-most item, outboard of the sort menu. Community feeds are embedded
    /// children whose host (`CommunityViewController`) owns the nav bar and
    /// provides its own community-prefilled "New post" button, and saved feeds
    /// have no single community to post to — both show only the sort menu.
    private func updateTrailingBarButtonItems() {
        guard case .frontpage = viewModel.feed.feedType else {
            navigationItem.rightBarButtonItems = [quickSwitchBarButtonItem, sortTypeBarButtonItem]
            return
        }
        let composeButton = UIBarButtonItem(
            image: UIImage(systemName: "square.and.pencil"),
            style: .plain,
            target: self,
            action: #selector(composeTapped)
        )
        // First item is the right-most: compose stays outboard, Quick Switch
        // sits immediately to its left, then the sort menu.
        navigationItem.rightBarButtonItems = [composeButton, quickSwitchBarButtonItem, sortTypeBarButtonItem]
    }

    // MARK: Feed title

    /// Set by the owning split controller (`MainWindowSplitViewController`) to
    /// present the feed switcher as a popover anchored to `anchor`. Wired only for
    /// the Posts-tab primary feed; nil elsewhere (e.g. the community-embedded feed,
    /// whose host owns the navbar). Used solely in the regular size class — in
    /// compact the switcher lives beneath the post list and is reached by the
    /// system back-swipe instead.
    var onPresentFeedSwitcher: ((_ anchor: UIView) -> Void)?

    /// The tappable feed-name title shown in the regular size class: the current
    /// feed name plus a trailing `chevron.down`, presenting the feed switcher as a
    /// popover on tap. Replaced by a plain `navigationItem.title` in compact width
    /// (and wherever `onPresentFeedSwitcher` is unset).
    private lazy var titleButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(
            systemName: "chevron.down",
            withConfiguration: UIImage.SymbolConfiguration(scale: .small)
        )
        config.imagePlacement = .trailing
        config.imagePadding = 4
        config.baseForegroundColor = .label
        config.contentInsets = .zero
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .preferredFont(forTextStyle: .headline)
            return outgoing
        }
        let button = UIButton(configuration: config)
        button.addTarget(self, action: #selector(titleTapped), for: .touchUpInside)
        button.accessibilityHint = NSLocalizedString(
            "Shows the feed switcher",
            comment: "Accessibility hint on the feed-name title button shown in the regular size class (iPad)"
        )
        return button
    }()

    /// Whether the tappable feed-name title control is currently installed.
    /// Tracked so the layout-pass re-evaluation only mutates `navigationItem` when
    /// the presentation mode actually flips.
    private var isShowingFeedTitleControl = false

    private func configureTitle() {
        applyNavigationTitle()
    }

    private func applyNavigationTitle() {
        applyTitleControl()
    }

    /// Installs either the tappable feed-name title control (the post list is the
    /// base of an EXPANDED split view and the feed switcher is reachable as a
    /// popover) or a plain title (a collapsed / compact single-column stack, where
    /// the switcher lives beneath the list via the system back-swipe; or an
    /// embedded feed whose host owns the navbar).
    ///
    /// Keyed on the containing split view's `isCollapsed`, NOT this controller's
    /// own `horizontalSizeClass`: in an expanded split the narrow primary column
    /// still reports a COMPACT horizontal size class, so the size class can't tell
    /// an "expanded primary column" apart from a "compact single column".
    /// True when the feed-title control (a tappable `UIButton` that opens the
    /// feed-switcher popover) should be shown instead of the plain navigation
    /// title. Evaluated from split-view collapse state, NOT from the primary
    /// column's own `horizontalSizeClass` (a narrow primary column in an expanded
    /// split still reports `.compact`, making the size class ambiguous here).
    private var shouldShowFeedTitleControl: Bool {
        splitViewController?.isCollapsed == false && onPresentFeedSwitcher != nil
    }

    private func applyTitleControl() {
        if shouldShowFeedTitleControl {
            titleButton.setTitle(viewModel.navigationTitle, for: .normal)
            titleButton.sizeToFit()
            navigationItem.titleView = titleButton
            navigationItem.title = nil
        } else {
            navigationItem.titleView = nil
            navigationItem.title = viewModel.navigationTitle
        }
        isShowingFeedTitleControl = shouldShowFeedTitleControl
    }

    /// Re-evaluates the title presentation mode and flips it only when it changed.
    /// Cheap enough to call on every layout pass — that is how a split
    /// collapse/expand (which changes the primary column's width but not this
    /// controller's `horizontalSizeClass`) is detected.
    private func refreshTitleControlModeIfNeeded() {
        guard shouldShowFeedTitleControl != isShowingFeedTitleControl else { return }
        applyTitleControl()
    }

    @objc
    private func titleTapped() {
        Haptics.tap()
        onPresentFeedSwitcher?(titleButton)
    }

    /// The feed currently displayed. The feed switcher reads this to mark the
    /// active row.
    var currentFeedType: FeedType {
        viewModel.feed.feedType
    }

    /// Switches the feed in place (feed-switcher selection), mirroring the sort-change
    /// path: swap the feed, restart the observation, and refresh the chrome.
    private func switchFeed(to feedType: FeedType) {
        viewModel.switchFeed(to: feedType)
        feedChanged()
        updateTrailingBarButtonItems()
        rebuildSortTypeMenu(activeSortType: viewModel.feed.feedType.sortType)
        applyNavigationTitle()
    }

    /// Switches the post list to a feed from outside the controller (deep links,
    /// App Intents). Mirrors the feed-switcher selection.
    func showFeed(_ feedType: FeedType) {
        switchFeed(to: feedType)
    }

    /// Starts the new-post composer (App Intent / external entry). Reuses the
    /// toolbar compose path, which applies the sign-in gate for signed-out users.
    func beginNewPost() {
        composeTapped()
    }

    @objc
    private func composeTapped() {
        let keychainId = viewModel.accountKeychainId
        guard !viewModel.accountScope.isSignedOut else {
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
        ) { [weak self] clientToken in
            guard let window = self?.view.window as? MainWindow else { return }
            window.displayPending(clientToken: clientToken, accountKeychainId: keychainId)
        }
        present(composer, animated: true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.refreshControl = refreshControl
        startObservations()
        feedChanged()

        // Backup trigger for the feed-name title control: re-evaluate on a
        // horizontal-size-class change (e.g. some iPad multitasking resizes). The
        // primary driver is `viewDidLayoutSubviews` (split collapse/expand changes
        // the column width, not this controller's size class). Uses the iOS 17+
        // registration API rather than the deprecated `traitCollectionDidChange(_:)`
        // override (which would warn).
        registerForTraitChanges([UITraitHorizontalSizeClass.self]) { (self: Self, _: UITraitCollection) in
            self.refreshTitleControlModeIfNeeded()
        }
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        // `splitViewController?.isCollapsed` is resolved by now; install the correct
        // title control for the current layout.
        applyTitleControl()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isViewVisible = true
        updateFeedPrivacy()
        seenFlushTimer?.invalidate()
        seenFlushTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.flushSeen() }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        isViewVisible = false
        updateFeedPrivacy()
        seenFlushTimer?.invalidate()
        seenFlushTimer = nil
        flushSeen()
    }

    /// True when the post is NSFW and the user has revealed its thumbnail this session.
    private func isRevealedNsfw(_ serverPostId: Int64) -> Bool {
        (viewModel.row(forServerPostId: serverPostId)?.isNsfw ?? false) && revealedNsfwPostIds.contains(serverPostId)
    }

    /// Registers feed sensitivity while a revealed NSFW thumbnail is on screen.
    private func updateFeedPrivacy() {
        feedSensitiveToken.set(isViewVisible && !visibleRevealedNsfwPostIds.isEmpty)
    }

    private func startObservations() {
        rowsObservationTask?.cancel()
        titleObservationTask?.cancel()
        loadStateObservationTask?.cancel()
        paginationStateObservationTask?.cancel()
        reachabilityObservationTask?.cancel()
        swipeActionsObservationTask?.cancel()
        for task in displayPrefsObservationTasks {
            task.cancel()
        }
        displayPrefsObservationTasks.removeAll()

        startRowsReaction()

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
            for await _ in ObservationStream.values(of: { viewModel.navigationTitle }) {
                if Task.isCancelled { break }
                self?.applyNavigationTitle()
            }
        }
        loadStateObservationTask = Task { @MainActor [weak self] in
            for await state in ObservationStream.values(of: { viewModel.loadState }) {
                if Task.isCancelled { break }
                self?.applyLoadState(state)
            }
        }
        paginationStateObservationTask = Task { @MainActor [weak self] in
            for await state in ObservationStream.values(of: { viewModel.paginationState }) {
                if Task.isCancelled { break }
                self?.applyPaginationState(state)
            }
        }
        reachabilityObservationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await online in reachabilityMonitor.statusStream {
                if Task.isCancelled { break }
                guard online else { continue }
                if case let .failed(failure) = viewModel.loadState, failure.kind == .offline {
                    feedChanged()
                }
            }
        }
    }

    /// Reacts to the view model's published `rowsRevision`, reproducing the
    /// per-emit render pipeline the GRDB loop used to run inline — in the same
    /// order: seed the hide-read pin from the first snapshot, then filter +
    /// snapshot-apply + applyLoadState (via `apply(rows:)`). The view model owns
    /// the GRDB observation now: on each emit it stores the rows into
    /// `orderedRows` (`@ObservationIgnored`) — rebuilding its `serverPostId`
    /// lookup atomically in the same turn — resolves the load state on EVERY emit
    /// BEFORE this reaction applies, and bumps `rowsRevision`, so that counter —
    /// not the rows — is the reaction key. Because the lookup lives on the view
    /// model alongside the rows, any interleaving `apply(rows:)` always sees a
    /// lookup consistent with the rows it renders.
    private func startRowsReaction() {
        rowsObservationTask?.cancel()
        rowsObservationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // The stream yields synchronously on subscribe (revision 0, before
            // any DB emit). Skip that seed value: only the increments a real DB
            // emit produces count as a feed snapshot.
            var lastHandledRevision = 0
            for await revision in ObservationStream.values(of: { [weak self] in
                self?.viewModel.rowsRevision ?? 0
            }) {
                if Task.isCancelled { break }
                guard revision != lastHandledRevision else { continue }
                lastHandledRevision = revision
                // Skip any delivery carrying a revision from before the last
                // `feedChanged` restart. This loop persists across feed switches,
                // so a pre-restart emit can still be enqueued when `feedChanged`
                // resets the seeding latch; applying it would seed the pin from
                // the reset-empty `firstSnapshotReadIds` and latch, so the new
                // feed's real first emit never seeds. `rowsRevision` is monotonic
                // and never reset, so the new observation's emits are strictly
                // greater and pass. Restores base's stale-emits-never-apply.
                guard revision > rowsRevisionAtRestart else { continue }

                if !hasSeededPinnedReadIds {
                    hasSeededPinnedReadIds = true
                    // Seed the pin from the view model's first-snapshot capture
                    // (computed on its exact first emit), so `onRefresh`
                    // hide-read only sweeps posts read before this feed view
                    // began. Must run before `apply(rows:)` uses `pinnedReadIds`.
                    pinnedReadIds = viewModel.firstSnapshotReadIds
                }
                // Live feed emissions never animate structurally. The first
                // snapshot would otherwise scale every cell in from the top-left
                // during the table's initial layout; a paginated insert would
                // animate the appended rows' height from zero as they scroll into
                // view. Cells whose data changed are reconfigured in place either
                // way. The deliberate hide-read toggle still animates its removals
                // (it calls `apply(rows:)` with the default `animatingDifferences`).
                apply(rows: viewModel.orderedRows, animatingDifferences: false)
            }
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
                pinnedReadIds = HideReadPostsFilter.readIds(in: viewModel.orderedRows)
                apply(rows: viewModel.orderedRows)
            }
        })

        displayPrefsObservationTasks.append(Task { @MainActor [weak self] in
            guard let self else { return }
            for await value in preferencesService.hideReadPostsModeStream {
                if Task.isCancelled { break }
                guard value != hideReadPostsMode else { continue }
                hideReadPostsMode = value
                apply(rows: viewModel.orderedRows)
            }
        })

        displayPrefsObservationTasks.append(Task { @MainActor [weak self] in
            guard let self else { return }
            for await value in preferencesService.groupCrossPostsInFeedStream {
                if Task.isCancelled { break }
                guard value != groupCrossPosts else { continue }
                groupCrossPosts = value
                // Re-runs the same pipeline `apply(rows:)` always does; turning
                // grouping off drops `crossPostSiblings` back to empty and
                // restores every collapsed sibling to the snapshot, turning it
                // on re-collapses them. `apply` recomputes `crossPostSiblings`
                // itself, so there's nothing else to re-seed here (unlike
                // hide-read's `pinnedReadIds`, which grouping doesn't touch).
                apply(rows: viewModel.orderedRows)
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

        // NSFW filtering is server-side (the `getPosts` request param), so a
        // change must re-fetch — `reloadFeed()` mints a fresh feed key and
        // re-pulls. The stream replays the current value on subscribe, so the
        // first element is skipped (no reload on launch); only subsequent
        // changes trigger a reload. For the frontpage feed only, also push the
        // new value to the server (best-effort) so the account's
        // `local_user.show_nsfw` stays in sync — gating to the frontpage avoids
        // duplicate server writes from the community / saved post lists that
        // also observe this stream.
        displayPrefsObservationTasks.append(Task { @MainActor [weak self] in
            guard let self else { return }
            var first = true
            for await value in preferencesService.showNsfwStream {
                if Task.isCancelled { break }
                if first { first = false
                    continue
                }
                reloadFeed()
                if case .frontpage = viewModel.feed.feedType,
                   !viewModel.accountScope.isSignedOut
                {
                    let scope = viewModel.accountScope
                    Task { try? await scope.lemmyService.setShowNsfw(value) }
                }
            }
        })

        // Blur is a pure render change — re-apply cells in-place without refetching.
        // The stream replays the current value on subscribe, so the first element is
        // skipped. For the frontpage feed, also push the new value to the server so
        // the account's `local_user.blur_nsfw` stays in sync.
        displayPrefsObservationTasks.append(Task { @MainActor [weak self] in
            guard let self else { return }
            var first = true
            for await value in preferencesService.blurNsfwStream {
                if Task.isCancelled { break }
                if first { first = false
                    continue
                }
                reconfigureVisibleCells()
                if case .frontpage = viewModel.feed.feedType,
                   !viewModel.accountScope.isSignedOut
                {
                    let scope = viewModel.accountScope
                    Task { try? await scope.lemmyService.setBlurNsfw(value) }
                }
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

    private func setupSortTypeMenu() {
        func makeAction(for sortType: Lemmy.SortType) -> UIAction {
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

        for sortType in PostSortMenu.all {
            _ = makeAction(for: sortType)
        }

        sortTypeBarButtonItem = UIBarButtonItem(
            title: "Sort type",
            image: UIImage(systemName: "line.horizontal.3.decrease.circle"),
            menu: nil
        )
        // Placement is owned by updateTrailingBarButtonItems() (called right after
        // this in setup()), which orders compose outboard of the sort menu.
        rebuildSortTypeMenu(activeSortType: viewModel.feed.feedType.sortType)
    }

    private func rebuildSortTypeMenu(activeSortType: Lemmy.SortType) {
        for (sortType, action) in sortTypeMenuActionsBySortType {
            action.state = (sortType == activeSortType) ? .on : .off
        }

        let sortTypeMenu = UIMenu(
            title: "",
            options: .singleSelection,
            children: [
                UIMenu(title: "", options: .displayInline, children: PostSortMenu.actives.compactMap { sortTypeMenuActionsBySortType[$0] }),
                UIMenu(title: "Top", options: .singleSelection, children: PostSortMenu.tops.compactMap { sortTypeMenuActionsBySortType[$0] }),
                UIMenu(title: "", options: .displayInline, children: PostSortMenu.comments.compactMap { sortTypeMenuActionsBySortType[$0] }),
            ]
        )

        sortTypeBarButtonItem.menu = sortTypeMenu
    }

    private func sortTypeChanged(to sortType: Lemmy.SortType) {
        viewModel.didChangeSortType(sortType)
        feedChanged()
        rebuildSortTypeMenu(activeSortType: viewModel.feed.feedType.sortType)
    }

    private func setupQuickSwitchButton() {
        quickSwitchBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "slider.horizontal.3"),
            style: .plain,
            target: self,
            action: #selector(quickSwitchTapped)
        )
    }

    @objc
    private func quickSwitchTapped() {
        Haptics.tap()
        let quickSwitchViewModel = QuickSwitchViewModel(
            preferencesService: preferencesService,
            currentSort: viewModel.feed.feedType.sortType,
            onSelectSort: { [weak self] sortType in
                self?.sortTypeChanged(to: sortType)
            },
            onDownloadForOffline: { [weak self] in
                // The popover dismisses itself before invoking this; defer to the
                // next runloop so the progress sheet presents from a settled state
                // rather than racing the popover's dismissal animation.
                DispatchQueue.main.async {
                    self?.startOfflineDownload()
                }
            }
        )
        let host = UIHostingController(rootView: QuickSwitchView(viewModel: quickSwitchViewModel))
        host.modalPresentationStyle = .popover
        host.sizingOptions = [.preferredContentSize]
        if let popover = host.popoverPresentationController {
            popover.sourceItem = quickSwitchBarButtonItem
            popover.delegate = forcePopoverDelegate
        }
        present(host, animated: true)
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
        Task { @MainActor [weak self] in
            guard let self else { return }
            let capability = await (
                try? viewModel.accountScope.lemmyService
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
        syncSkeletonHeaderInset()
        tableView.backgroundView = loadingSkeletonView
        loadingSkeletonView.startAnimating()
    }

    /// Insets the loading skeleton below the scrolling header (if any). The
    /// skeleton is the table's `backgroundView`, which sits behind the
    /// `tableHeaderView`, so without this the opaque community header would cover
    /// the skeleton's top rows. Re-applied whenever the header is (re)measured.
    private func syncSkeletonHeaderInset() {
        loadingSkeletonView.topInset = scrollingHeaderView?.frame.height ?? 0
    }

    private func hideLoadingSkeleton() {
        guard tableView.backgroundView === loadingSkeletonView else { return }
        loadingSkeletonView.stopAnimating()
        tableView.backgroundView = nil
    }

    private lazy var stateSurfaceView = FeedStateSurfaceView()

    /// Presents the full empty / error state by hosting it in the table's
    /// `backgroundView` (the slot the loading skeleton also uses), rather than the
    /// view-controller-level `contentUnavailableConfiguration`. That overlay is a
    /// TRANSPARENT view drawn across the WHOLE controller view, including a
    /// scrolling header hosted as the table's `tableHeaderView` (the community
    /// header), so the error copy rendered see-through ON TOP of the header — the
    /// shipped bug this fixes. The `backgroundView` sits BELOW the header in
    /// z-order; the header-height top inset (see `syncStateSurfaceHeaderInset`)
    /// then centers the surface within the below-header region. Mirrors
    /// `PersonViewController.updateContentUnavailable` (commit b7ecc4ce). The
    /// button actions ride the same `UIContentUnavailableConfiguration` rendered
    /// by the same `UIContentUnavailableView` the VC-level overlay used, so
    /// `makeErrorConfiguration(for:)` is reused unchanged.
    ///
    /// Symmetric with the skeleton's `===`-guarded set/clear so the two never
    /// clobber each other in the shared slot: this only installs itself
    /// (replacing whatever is there) and `hideStateSurface` only clears when it
    /// owns the slot. `contentUnavailableConfiguration` stays permanently nil.
    private func showStateSurface(_ config: UIContentUnavailableConfiguration) {
        syncStateSurfaceHeaderInset()
        stateSurfaceView.setContentView(config.makeContentView())
        if tableView.backgroundView !== stateSurfaceView {
            tableView.backgroundView = stateSurfaceView
        }
    }

    /// Insets the state surface below the scrolling header (if any), mirroring
    /// `syncSkeletonHeaderInset()` — the surface is the table's `backgroundView`,
    /// which sits behind the `tableHeaderView`, so this keeps it centered in the
    /// visible below-header region instead of behind an opaque, possibly tall,
    /// header. Zero for a header-less feed.
    private func syncStateSurfaceHeaderInset() {
        stateSurfaceView.topInset = scrollingHeaderView?.frame.height ?? 0
    }

    private func hideStateSurface() {
        guard tableView.backgroundView === stateSurfaceView else { return }
        tableView.backgroundView = nil
    }

    @objc
    private func refreshTriggered() {
        // Pull-to-refresh re-pulls the feed from the top via a fresh feed key,
        // keeping the current posts on screen until the new content swaps in.
        viewModel.didClickReload()
        feedChanged(keepingContent: true)
    }

    private func feedChanged(keepingContent: Bool = false) {
        // The saved scroll-undo position belongs to the prior feed; a feed swap
        // makes it stale. Drop it (and its hint toast) before reloading.
        let hadArmedUndo = scrollUndo.pending != nil
        scrollUndo.invalidate()
        if hadArmedUndo {
            ToastPresenter.shared.dismiss()
        }

        viewModel.prepareForReload()
        // A pull-to-refresh keeps the existing posts on screen — the refresh
        // control is the only progress indicator — until the new feed's first
        // snapshot swaps them in. On a non-keeping change the view model clears
        // its rows + `serverPostId` lookup; this clears the diffable snapshot in
        // lockstep (a cell re-dequeued with an empty lookup renders "Missing
        // PostListRow" — see `clearPostItems`). The snapshot is cleared before
        // the view model resets its lookup (both synchronous, no await between),
        // so the dangerous lookup-empty-but-snapshot-populated window never opens.
        if !keepingContent {
            displayedRows.removeAll()
            // `crossPostSiblings` is auxiliary lookup state for rows already in
            // `displayedRows` (see its doc comment) — reset it in lockstep so a
            // stale sibling map from the prior feed can't outlive the rows it
            // was computed from.
            crossPostSiblings.removeAll()
            clearPostItems()
        }
        viewModel.restartObservations(keepingContent: keepingContent)
        // Read-id pins belong to the prior feed session, so they reset either
        // way; the new first snapshot re-seeds `pinnedReadIds` from the view
        // model's `firstSnapshotReadIds` on the first row reaction.
        pinnedReadIds.removeAll()
        markedReadIds.removeAll()
        hasSeededPinnedReadIds = false
        // Capture the current revision alongside the latch reset: the rows
        // reaction skips any delivery at or below this, so a pre-restart emit
        // enqueued before this reset can't seed the (now-reset-empty) pin. The
        // new observation's first emit bumps `rowsRevision` strictly past this.
        rowsRevisionAtRestart = viewModel.rowsRevision
        if !keepingContent {
            showLoadingSkeleton()
        }
        refreshModerationCapability()
    }

    /// Renders a feed snapshot: filters `rows` for the hide-read preference,
    /// then (preference-gated) collapses cross-post duplicates via
    /// `CrossPostGrouper` into `displayedRows` + `crossPostSiblings`, applies the
    /// diffable snapshot (reconfiguring surviving cells in place), and
    /// re-evaluates the top-level load state. The view model owns the ordered
    /// snapshot + the `serverPostId` lookup (already stored when this runs) for
    /// EVERY row, including collapsed siblings — this only reads them via the
    /// passed `rows`. Called from the row reaction (a DB emit,
    /// `animatingDifferences: false`) and the display-preference reactions (a
    /// hide-read or grouping toggle re-filtering the same `viewModel.orderedRows`,
    /// keeping the default animation for the resulting removals/insertions).
    private func apply(rows: [PostListRow], animatingDifferences: Bool = true) {
        // Filter for display per the hide-read preference. The view model's
        // `serverPostId` lookup still maps every row so cells resolve, but the
        // snapshot only carries the rows that should be visible.
        let filtered = HideReadPostsFilter.filter(
            rows: rows,
            enabled: hideReadPosts,
            mode: hideReadPostsMode,
            pinnedReadIds: pinnedReadIds
        )

        // Cross-post grouping runs AFTER the hide-read filter, so a read/hidden
        // row already dropped above can never anchor a group as a primary or be
        // counted as a sibling. Preference-gated: when off, skip the transform
        // entirely (`filtered` passes through unchanged) rather than calling
        // `CrossPostGrouper.group` and discarding its result — the grouper
        // itself has no "disabled" mode.
        let grouped = groupCrossPosts
            ? CrossPostGrouper.group(rows: filtered)
            : CrossPostGrouper.Result(displayed: filtered, siblingsByPrimary: [:])
        crossPostSiblings = grouped.siblingsByPrimary
        displayedRows = grouped.displayed

        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.posts])
        let items = grouped.displayed.map { Item.post(serverPostId: $0.serverPostId) }
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

        // The `.loading` section (pagination spinner / retry footer) is owned
        // solely by applyPaginationState; this snapshot only carries posts.
        dataSource.apply(snapshot, animatingDifferences: animatingDifferences)

        // A row change can flip loaded <-> empty, so re-evaluate the top-level
        // load state after every snapshot.
        applyLoadState(viewModel.loadState)
    }

    /// Renders the feed's top-level load state: skeleton + slow caption while
    /// loading, the designed empty state when settled-and-empty, and the
    /// presenter-driven error surface when the initial load failed. The skeleton
    /// and the content-unavailable surface are mutually exclusive.
    ///
    /// `internal` (not `private`) ONLY so `PostListStateSurfaceTests` can drive a
    /// state directly and assert where the surface renders — the live update path
    /// (the async `loadStateObservationTask`) is not synchronously drivable. Not
    /// public API; treat as private to this file plus that one test seam.
    func applyLoadState(_ state: FeedLoadState) {
        switch state {
        case let .loading(slow):
            // During a pull-to-refresh the control is the only progress
            // indicator; keep the existing posts and skip the skeleton.
            if !refreshControl.isRefreshing {
                showLoadingSkeleton()
                loadingSkeletonView.setShowsSlowHint(slow)
            }
            hideStateSurface()
        case .loaded:
            refreshControl.endRefreshing()
            hideLoadingSkeleton()
            hideStateSurface()
        case .empty:
            refreshControl.endRefreshing()
            hideLoadingSkeleton()
            let empty = viewModel.emptyState
            var config = UIContentUnavailableConfiguration.empty()
            config.image = UIImage(systemName: empty.symbolName)
            config.text = empty.title
            config.secondaryText = empty.message
            showStateSurface(config)
        case let .failed(failure):
            // Never replace on-screen posts with the full error surface: it's a
            // transparent `UIContentUnavailableConfiguration`, so overlaying it on
            // live posts renders the error copy see-through on top of them. When
            // the feed already has content (`displayedRows` still holds the prior
            // feed until a new feed's first snapshot swaps it in), keep it and
            // surface the failure as a transient toast; only fall back to the full
            // surface when the list is empty (a normal initial-load failure), where
            // there is nothing behind it. Gating on `displayedRows` alone — not on
            // `refreshControl.isRefreshing` — is what makes this hold for any reload
            // path (reconnect retry, in-place feed switch) and immune to a racing
            // `endRefreshing()` that clears the flag while posts remain.
            refreshControl.endRefreshing()
            switch FeedFailurePresentation.decide(hasContent: !displayedRows.isEmpty) {
            case .keepContentWithToast:
                showRefreshFailureToast(for: failure)
            case .fullErrorSurface:
                hideLoadingSkeleton()
                showStateSurface(makeErrorConfiguration(for: failure))
            }
        }
    }

    /// Renders a `LoadFailure` into a content-unavailable configuration via the
    /// `FeedStatePresenter`, wiring each descriptor action to a controller
    /// closure.
    private func makeErrorConfiguration(for failure: LoadFailure) -> UIContentUnavailableConfiguration {
        let descriptor = FeedStatePresenter.descriptor(
            for: failure.kind,
            host: viewModel.instanceHost,
            hasDownloadedContent: viewModel.hasDownloadedContent
        )
        var config = UIContentUnavailableConfiguration.empty()
        config.image = UIImage(systemName: descriptor.symbolName)
        config.text = descriptor.title
        config.secondaryText = descriptor.message

        var primary = UIButton.Configuration.borderedProminent()
        primary.title = descriptor.primary.title
        primary.baseBackgroundColor = ThemeManager.currentAccentColor
        config.button = primary
        config.buttonProperties.primaryAction = action(for: descriptor.primary.action, failure: failure)

        if let secondary = descriptor.secondary {
            var secondaryConfig = UIButton.Configuration.plain()
            secondaryConfig.title = secondary.title
            config.secondaryButton = secondaryConfig
            config.secondaryButtonProperties.primaryAction = action(for: secondary.action, failure: failure)
        }
        return config
    }

    /// Surfaces a failed pull-to-refresh as a transient toast, keeping the
    /// existing posts on screen.
    private func showRefreshFailureToast(for failure: LoadFailure) {
        guard let window = view.window else { return }
        let message = failure.kind == .offline
            ? NSLocalizedString("You're offline", comment: "Toast when pull-to-refresh fails while offline")
            : NSLocalizedString("Couldn't refresh", comment: "Toast when pull-to-refresh fails")
        ToastPresenter.shared.show(message, in: window)
    }

    private func action(for action: FeedErrorDescriptor.Action, failure: LoadFailure) -> UIAction {
        switch action {
        case .retry:
            return UIAction { [weak self] _ in self?.feedChanged() }
        case .workOffline:
            return UIAction { [weak self] _ in
                guard let self else { return }
                // Dismiss the error and show the empty state for this feed.
                viewModel.dismissToEmpty()
                applyLoadState(viewModel.loadState)
            }
        case .copyDetails:
            return UIAction { [weak self] _ in
                UIPasteboard.general.string = self?.viewModel.lastFailureDiagnostics
            }
        case .viewDownloaded:
            return UIAction { [weak self] _ in
                guard let self else { return }
                // Route to the local-only Downloaded feed (network-free), reusing
                // the in-place feed switch the feed switcher uses. Carry the
                // current sort for parity; the feed always orders by download date.
                showFeed(.downloaded(sortType: viewModel.feed.feedType.sortType))
            }
        }
    }

    /// Clears the displayed posts from the diffable snapshot, keeping the
    /// snapshot and the view model's `serverPostId` lookup in lockstep. Without
    /// this, switching feeds leaves the prior feed's `.post` items in the
    /// snapshot while the view model has emptied its lookup, so any cell
    /// re-dequeued before the new feed's first snapshot resolves to no row
    /// ("Missing PostListRow").
    /// The `.loading` section (pagination footer) is owned by applyPaginationState
    /// and left untouched.
    private func clearPostItems() {
        guard dataSource != nil else { return }
        var snapshot = dataSource.snapshot()
        guard snapshot.sectionIdentifiers.contains(.posts) else { return }
        snapshot.deleteSections([.posts])
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    /// Renders the pagination footer section from `paginationState`: a loading
    /// spinner footer, an inline retry footer on failure, and nothing when idle.
    /// Owns the `.loading` section exclusively.
    private func applyPaginationState(_ state: PaginationState) {
        guard dataSource != nil else { return }
        var snapshot = dataSource.snapshot()
        if snapshot.sectionIdentifiers.contains(.loading) {
            snapshot.deleteSections([.loading])
        }
        switch state {
        case .idle:
            break
        case .loading:
            snapshot.appendSections([.loading])
            snapshot.appendItems([.loadingIndicator], toSection: .loading)
        case .failed:
            snapshot.appendSections([.loading])
            snapshot.appendItems([.paginationRetry], toSection: .loading)
        }
        dataSource.apply(snapshot, animatingDifferences: true)
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

                guard let row = self?.viewModel.row(forServerPostId: serverPostId) else {
                    logger.assertionFailure("Missing PostListRow for serverPostId \(serverPostId)")
                    return cell
                }

                let viewModel = PostListPostViewModel(
                    row: row,
                    appearance: appearance,
                    postContentDetector: postContentDetector,
                    blurNsfw: self?.preferencesService.blurNsfw ?? false,
                    isRevealed: self?.revealedNsfwPostIds.contains(serverPostId) ?? false,
                    crossPostSiblingCommunityNames: (self?.crossPostSiblings[serverPostId] ?? [])
                        .map(\.communityName)
                )
                cell.configure(with: viewModel, imageService: imageService)
                cell.seenTrackingServerPostId = serverPostId

                cell.revealNsfwTapped = { [weak self] in
                    guard let self else { return }
                    revealedNsfwPostIds.insert(serverPostId)
                    // The revealed cell is on screen now — it's sensitive content.
                    visibleRevealedNsfwPostIds.insert(serverPostId)
                    updateFeedPrivacy()
                    var snapshot = dataSource.snapshot()
                    snapshot.reconfigureItems([item])
                    dataSource.apply(snapshot, animatingDifferences: false)
                }

                cell.imageTapped = { [weak self] imageUrl, thumbnailUrl, thumbnailImage in
                    guard let self else { return }
                    presentMediaViewer(
                        imageUrl: imageUrl,
                        thumbnailUrl: thumbnailUrl,
                        preloadedImage: thumbnailImage,
                        altText: row.altText,
                        isNsfw: row.isNsfw
                    )
                    // Viewing a post's media counts as opening it, so mark it
                    // read like tapping into the post does (master toggle only).
                    if markPostsRead {
                        markReadInBackground(serverPostId: serverPostId)
                    }
                }

                cell.videoTapped = { [weak self] videoUrl in
                    guard let self else { return }
                    Task { await self.playVideo(url: videoUrl, appService: self.appService) }
                    if markPostsRead {
                        markReadInBackground(serverPostId: serverPostId)
                    }
                }

                cell.linkTapped = { [weak self] linkUrl in
                    guard let self else { return }
                    openExternalLink(linkUrl)
                    // Opening the post's link counts as consuming it, like
                    // opening the post detail does (master toggle only).
                    if markPostsRead {
                        markReadInBackground(serverPostId: serverPostId)
                    }
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

            case .paginationRetry:
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: PaginationErrorFooterCell.reuseIdentifier,
                    for: indexPath
                ) as! PaginationErrorFooterCell
                cell.onRetry = { [weak self] in
                    Task { await self?.viewModel.retryPagination() }
                }
                return cell
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
        guard !viewModel.accountScope.isSignedOut else {
            presentSignInGate(
                title: NSLocalizedString("Sign in to comment", comment: "Sign-in gate title when a signed-out user tries to comment")
            )
            return
        }
        Haptics.tap()
        let composer = ComposerViewController.makeSheet(
            target: .postReply(serverPostId: Lemmy.PostID(serverPostId)),
            accountKeychainId: keychainId,
            dependencies: dependencies.own
        )
        present(composer, animated: true)
    }

    /// Opens the new-post composer pre-filled with the post's title + url, so
    /// the user can re-share it to another community. The feed row carries no
    /// body, so the attribution is title + url only (matches lemmy-ui for a
    /// no-body post) — the post-detail overflow menu's cross-post action
    /// includes the quoted body since the full post is loaded there.
    private func crossPostPost(serverPostId: Int64) {
        let keychainId = viewModel.accountKeychainId
        guard !viewModel.accountScope.isSignedOut else {
            presentSignInGate(
                title: NSLocalizedString("Sign in to post", comment: "Sign-in gate title when a signed-out user tries to cross-post")
            )
            return
        }
        guard let row = viewModel.row(forServerPostId: serverPostId) else {
            Haptics.warning()
            return
        }

        Haptics.tap()
        let composer = NewPostViewController.makeCrossPostSheet(
            initialTitle: row.title,
            initialUrl: row.url,
            initialBody: crossPostBody(originalApId: row.originalPostUrl, originalBody: nil),
            accountKeychainId: keychainId,
            dependencies: dependencies.own
        ) { [weak self] clientToken in
            guard let window = self?.view.window as? MainWindow else { return }
            window.displayPending(clientToken: clientToken, accountKeychainId: keychainId)
        }
        present(composer, animated: true)
    }

    /// Pushes the post's community screen. Browsing is allowed signed-out, so
    /// this is not gated.
    private func visitCommunity(serverPostId: Int64) {
        guard
            let row = viewModel.row(forServerPostId: serverPostId),
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
            let row = viewModel.row(forServerPostId: serverPostId),
            let actorId = row.creatorActorId,
            let instance = InstanceActorId(from: actorId)
        else {
            Haptics.warning()
            return
        }
        Haptics.tap()
        let vc = PersonOrLoadingViewController(
            personId: Lemmy.PersonID(row.creatorPersonId),
            instance: instance,
            accountKeychainId: viewModel.accountKeychainId,
            dependencies: dependencies.nested
        )
        navigationController?.pushViewController(vc, animated: true)
    }

    /// Reports the post, gating on sign-in. Mirrors the post-detail report
    /// flow: a required-reason alert, then a confirmation.
    private func reportPost(serverPostId: Int64) {
        guard !viewModel.accountScope.isSignedOut else {
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
            try await viewModel.accountScope.lemmyService
                .reportPost(serverPostId: Lemmy.PostID(serverPostId), reason: reason)
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
        guard !viewModel.accountScope.isSignedOut else {
            presentSignInGate(
                title: NSLocalizedString("Sign in to block", comment: "Sign-in gate title when a signed-out user tries to block")
            )
            return
        }
        guard let row = viewModel.row(forServerPostId: serverPostId) else { return }
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
            try await viewModel.accountScope.lemmyService
                .setBlocked(serverPersonId: Lemmy.PersonID(serverPersonId), blocked: true)
        } catch {
            alertService.handle(error, for: .setBlockedPerson)
        }
    }

    /// Hides the post, gating on sign-in then on the `.hidePosts` capability
    /// (Lemmy 1.0's v3 compat shim doesn't have `/post/hide`). The hidden flag
    /// is server-backed; on success the GRDB observation re-emits without the
    /// row, so it drops out of the feed.
    private func hidePost(serverPostId: Int64) {
        guard !viewModel.accountScope.isSignedOut else {
            presentSignInGate(
                title: NSLocalizedString("Sign in to hide posts", comment: "Sign-in gate title when a signed-out user tries to hide a post")
            )
            return
        }
        // Read live at action time (no caching in the VC) - see AccountScope's
        // doc comment.
        guard viewModel.accountScope.capabilities.can(.hidePosts) else {
            presentCapabilityGate(
                for: .hidePosts,
                host: viewModel.accountScope.instanceActorId?.hostWithPort,
                sourceView: nil
            )
            return
        }
        Task { await performHidePost(serverPostId: serverPostId) }
    }

    private func performHidePost(serverPostId: Int64) async {
        Haptics.tap()
        do {
            try await viewModel.accountScope.lemmyService
                .hidePost(serverPostId: Lemmy.PostID(serverPostId), hidden: true)
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
            let row = viewModel.row(forServerPostId: serverPostId),
            let actorId = row.communityActorId
        else {
            Haptics.warning()
            return
        }
        Haptics.tap()
        viewModel.muteCommunity(communityActorId: actorId, until: duration.until)
    }

    /// Shares the post's canonical URL. Prefers the post's `ap_id` permalink;
    /// falls back to constructing it from the account instance.
    private func sharePost(serverPostId: Int64) {
        let instanceActorId = viewModel.instanceActorId
        guard let url = LinkURL.forPost(
            instance: preferencesService.shareLinkInstance,
            originalPostUrl: viewModel.row(forServerPostId: serverPostId)?.originalPostUrl,
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
            serverPostId: Lemmy.PostID(serverPostId),
            accountKeychainId: viewModel.accountKeychainId
        )
    }

    /// Thin forwarder so existing call sites stay unchanged; the logic lives in
    /// `UIViewController+MediaViewer.swift`.
    private func presentMediaViewer(
        imageUrl: URL,
        thumbnailUrl: URL?,
        preloadedImage: UIImage?,
        altText: String? = nil,
        isNsfw: Bool = false
    ) {
        presentMediaViewer(
            imageUrl: imageUrl,
            thumbnailUrl: thumbnailUrl,
            preloadedImage: preloadedImage,
            altText: altText,
            isNsfw: isNsfw,
            dependencies: dependencies.own
        )
    }

    /// Opens an external-link post's url, honoring the user's "Open External
    /// Links in" preference (in-app Safari / browser / reader mode).
    private func openExternalLink(_ url: URL) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await appService.open(url: url, on: self)
        }
    }

    private func flushSeen() {
        let seen = seenDwellTracker.flushSeen(at: Date())
        guard !seen.isEmpty else { return }
        recordSeen(seen)
    }

    /// Persists "seen" for the given server post ids, building each snapshot from
    /// the currently-loaded feed row. Fire-and-forget; failures are non-fatal.
    private func recordSeen(_ serverPostIds: [Int64]) {
        let snapshots: [(Int64, PostInteractionSnapshot)] = serverPostIds.compactMap { id in
            guard let row = viewModel.row(forServerPostId: id) else { return nil }
            return (id, PostInteractionSnapshot(postListRow: row))
        }
        guard !snapshots.isEmpty else { return }
        Task { [viewModel] in
            for (id, snapshot) in snapshots {
                await viewModel.recordSeen(serverPostId: id, snapshot: snapshot)
            }
        }
    }
}

// MARK: - PostSaveDispatching

extension PostListViewController: PostSaveDispatching {
    var postActionsAccountScope: AccountScope {
        viewModel.accountScope
    }

    var postActionsAlertService: AlertServiceType {
        alertService
    }

    func currentSavedState(serverPostId: Int64) -> Bool {
        viewModel.row(forServerPostId: serverPostId)?.isSaved ?? false
    }
}

// MARK: - PostReminderDispatching

/// Folds the feed's "Remind Me…" context-menu item into the shared dispatch
/// protocol so it goes through the same `ReminderService` calls the post
/// detail overflow menu uses. The context menu is rebuilt fresh on every
/// long-press (`contextMenuConfigurationForRowAt`), so unlike post detail's
/// cached overflow-menu button, there's nothing to explicitly rebuild here.
extension PostListViewController: PostReminderDispatching {
    func remindMeMenuDidChange() { }

    /// The whole-post fields for the "Remind Me…" menu, built from the feed
    /// row at `serverPostId` - nil if the row isn't loaded (long-press raced
    /// a row eviction), in which case the caller omits the submenu.
    fileprivate func remindMeMenuTarget(serverPostId: Int64) -> RemindMeMenuTarget? {
        guard let row = viewModel.row(forServerPostId: serverPostId) else { return nil }
        // Prefer the community's own instance host; a community row with no
        // resolvable actorId (rare) falls back to the account's home
        // instance so `instanceHost` is never left empty.
        let instanceHost = row.communityActorId.flatMap { InstanceActorId(from: $0)?.host }
            ?? viewModel.accountScope.instanceActorId?.host
            ?? ""
        return RemindMeMenuTarget(
            postServerId: row.serverPostId,
            apId: row.originalPostUrl,
            title: row.title,
            communityName: row.communityName,
            instanceHost: instanceHost,
            thumbnailUrl: row.thumbnailUrl
        )
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

    func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
        switch scrollUndo.statusBarTapped(
            currentOffset: scrollView.contentOffset,
            topVisibleServerPostId: topmostVisibleServerPostId()
        ) {
        case .undo:
            performScrollUndo()
            return false
        case .allowScrollToTop:
            return true
        }
    }

    func scrollViewDidScrollToTop(_ scrollView: UIScrollView) {
        guard scrollUndo.scrolledToTop(viewportHeight: scrollView.bounds.height) != nil else {
            return
        }
        showUndoScrollToast()
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        // A manual scroll disarms the toggle (and its hint toast), but keeps the
        // deepest saved position: scrolling partway back down toward where you
        // were is part of recovering, so a later status-bar tap can still offer to
        // return there. Only touch the toast when we actually had one armed.
        let wasArmed = scrollUndo.pending != nil
        scrollUndo.userDidScroll()
        if wasArmed {
            ToastPresenter.shared.dismiss()
        }
    }

    /// The server post id of the topmost currently-visible post row - the row to
    /// pulse on restore. `nil` when no post row is visible (e.g. only the loading
    /// footer), which suppresses the undo for that tap.
    ///
    /// "Substantially visible" was the original spec intent, but using the first
    /// visible post is deliberate here: the content-offset restore is exact, so
    /// this anchor only determines which row to *pulse* on restore. The topmost
    /// visible post is a correct and cheap choice.
    private func topmostVisibleServerPostId() -> Int64? {
        for indexPath in tableView.indexPathsForVisibleRows ?? [] {
            if case let .post(serverPostId)? = dataSource.itemIdentifier(for: indexPath) {
                return serverPostId
            }
        }
        return nil
    }

    private func showUndoScrollToast() {
        guard let window = view.window else { return }
        UIAccessibility.post(
            notification: .announcement,
            argument: NSLocalizedString(
                "Jumped to top",
                comment: "Accessibility announcement when a status-bar tap scrolled the feed to the top"
            )
        )
        ToastPresenter.shared.show(
            NSLocalizedString(
                "Jumped to top",
                comment: "Undo toast title shown after an accidental scroll-to-top"
            ),
            actionTitle: NSLocalizedString(
                "Undo",
                comment: "Undo button on the scroll-to-top toast"
            ),
            in: window,
            action: { [weak self] in self?.performScrollUndo() }
        )
    }

    /// Snaps instantly back to the saved position, pulses the anchored row, and
    /// confirms. Shared by the toast "Undo" button and the status-bar toggle.
    private func performScrollUndo() {
        guard let pending = scrollUndo.takeUndo() else { return }
        tableView.setContentOffset(pending.offset, animated: false)
        tableView.layoutIfNeeded()
        if let indexPath = dataSource.indexPath(for: .post(serverPostId: pending.anchorServerPostId)),
           let cell = tableView.cellForRow(at: indexPath)
        {
            cell.contentView.pulseHighlight()
        }
        if let window = view.window {
            ToastPresenter.shared.show(
                NSLocalizedString(
                    "Back to where you were",
                    comment: "Confirmation toast after undoing an accidental scroll-to-top"
                ),
                in: window
            )
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard case let .post(serverPostId) = dataSource.itemIdentifier(for: indexPath) else { return }
        postSelected(serverPostId: serverPostId)
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard case let .post(serverPostId) = dataSource.itemIdentifier(for: indexPath) else { return }
        seenDwellTracker.didAppear(serverPostId: serverPostId, at: Date())
        if isRevealedNsfw(serverPostId) {
            visibleRevealedNsfwPostIds.insert(serverPostId)
            updateFeedPrivacy()
        }
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
        // Seen-on-screen capture: read the post id stamped on the cell at
        // configure time — dataSource.itemIdentifier(for:) is unreliable here
        // because the snapshot may have changed since the cell was displayed.
        if let serverPostId = (cell as? PostListPostCell)?.seenTrackingServerPostId,
           let seen = seenDwellTracker.didDisappear(serverPostId: serverPostId, at: Date())
        {
            recordSeen([seen])
        }

        // A revealed NSFW thumbnail left the screen — drop it from the privacy set.
        if let serverPostId = (cell as? PostListPostCell)?.seenTrackingServerPostId,
           visibleRevealedNsfwPostIds.remove(serverPostId) != nil
        {
            updateFeedPrivacy()
        }

        guard markPostsRead, markPostsReadOnScroll else { return }
        // The cell has already left the data source's reach by the time this
        // fires after a snapshot apply, so resolve the post id from the cell's
        // last-known item rather than `itemIdentifier(for:)`.
        guard let item = dataSource.itemIdentifier(for: indexPath),
              case let .post(serverPostId) = item else { return }
        markReadInBackground(serverPostId: serverPostId)
    }

    /// Fires a best-effort server mark-as-read for a post the user has implicitly
    /// consumed (scrolled past, or opened its media). Deduped per session and
    /// short-circuited for rows already read; the new read state flows back
    /// through the GRDB observation. Callers gate on the relevant preference.
    private func markReadInBackground(serverPostId: Int64) {
        // The Downloaded feed is a local, offline library — usually browsed with
        // no network — so firing a server mark-as-read would only make doomed
        // requests. Skip it there entirely (keeps the feed genuinely network-free).
        guard !viewModel.isDownloadedFeed else { return }
        // Skip rows already read or already enqueued this session.
        guard !markedReadIds.contains(serverPostId) else { return }
        if viewModel.row(forServerPostId: serverPostId)?.isRead == true {
            markedReadIds.insert(serverPostId)
            return
        }
        markedReadIds.insert(serverPostId)

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await viewModel.accountScope.lemmyService
                    .markAsRead(serverPostId: Lemmy.PostID(serverPostId))
            } catch {
                // Best-effort: a failed mark-read should not interrupt
                // browsing. Allow a later retry by un-enqueuing.
                markedReadIds.remove(serverPostId)
                logger.debug("Background mark-as-read failed: \(String(describing: error), privacy: .public)")
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
            let row = viewModel.row(forServerPostId: serverPostId)
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

                let isSaved = self?.viewModel.row(forServerPostId: serverPostId)?.isSaved ?? false
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

                let crossPostAction = UIAction(
                    title: NSLocalizedString("Cross-post", comment: "Context-menu action to re-share a post to another community"),
                    image: UIImage(systemName: "arrow.triangle.branch")
                ) { [weak self] _ in
                    self?.crossPostPost(serverPostId: serverPostId)
                }

                let row = self?.viewModel.row(forServerPostId: serverPostId)

                let visitCommunityAction = UIAction(
                    title: String(
                        format: NSLocalizedString("Visit %@", comment: "Context-menu action to open a post's community; %@ is the c/ community handle"),
                        // Map over the optional `row`, not `row?.communityName`:
                        // `communityName` is a non-optional String, so
                        // `row?.communityName.map` would resolve to Collection.map
                        // (over Characters) and render as an array description.
                        row.map { "c/\($0.communityName)" } ?? NSLocalizedString("community", comment: "Generic community noun")
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
                var voteChildren: [UIMenuElement] = [upvoteAction, downvoteAction, saveAction]
                if let self, let target = remindMeMenuTarget(serverPostId: serverPostId) {
                    voteChildren.append(makeRemindMeMenu(for: target))
                }
                let voteGroup = UIMenu(options: .displayInline, children: voteChildren)
                let shareGroup = UIMenu(options: .displayInline, children: [replyAction, shareAction, crossPostAction])
                var navChildren: [UIMenuElement] = [visitCommunityAction, viewAuthorAction]
                // "Also posted in" jump submenu — only when this post is a
                // cross-post-grouping primary with collapsed siblings. Task 1's
                // `crossPostAction` above CREATES a new cross-post; this
                // navigates to ones that already exist, so the two never
                // conflate despite sharing a symbol.
                if let crossPostMenu = self?.crossPostSiblingsMenu(serverPostId: serverPostId) {
                    navChildren.append(crossPostMenu)
                }
                let navGroup = UIMenu(options: .displayInline, children: navChildren)
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

    // MARK: Cross-post grouping

    /// The "Also posted in" jump submenu for the post at `serverPostId`, or nil
    /// when it isn't a cross-post-grouping primary (no collapsed siblings —
    /// either it wasn't grouped, or grouping is off, in which case
    /// `crossPostSiblings` is empty). Each child opens a sibling post via
    /// `postSelected(serverPostId:)`, the same path a feed tap uses — that path
    /// resolves by `serverPostId` alone (`window.display(serverPostId:...)`), so
    /// it works whether or not the sibling itself is currently on screen.
    private func crossPostSiblingsMenu(serverPostId: Int64) -> UIMenu? {
        guard let siblings = crossPostSiblings[serverPostId], !siblings.isEmpty else { return nil }

        let children = siblings.map { sibling in
            UIAction(
                title: Self.qualifiedCommunityHandle(for: sibling),
                // `square.on.square` (stacked copies) distinguishes JUMPING to an
                // existing cross-post from the `arrow.triangle.branch` CREATE action
                // that composes a new one.
                image: UIImage(systemName: "square.on.square")
            ) { [weak self] _ in
                self?.postSelected(serverPostId: sibling.serverPostId)
            }
        }
        return UIMenu(
            title: NSLocalizedString(
                "Also posted in",
                comment: "Context-menu submenu listing a post's collapsed cross-post siblings"
            ),
            image: UIImage(systemName: "square.on.square"),
            children: children
        )
    }

    /// `c/<community>@<instance>`, or just `c/<community>` when the row's actor
    /// id can't be parsed to a host. Mirrors the `@instance` suffix convention
    /// the feed subtitle and the "Cross-posted to N communities" post-detail
    /// section both use.
    private static func qualifiedCommunityHandle(for row: PostListRow) -> String {
        guard
            let actorId = row.communityActorId,
            let instance = InstanceActorId(from: actorId)
        else {
            return "c/\(row.communityName)"
        }
        return "c/\(row.communityName)@\(instance.host)"
    }

    // MARK: Moderation

    /// The moderation menu for the post at `serverPostId`, or nil when the
    /// account cannot moderate its community. Offers Remove/Restore,
    /// Lock/Unlock, Pin to community, and (admins) Pin to instance.
    private func postModerationMenu(serverPostId: Int64) -> UIMenu? {
        guard let row = viewModel.row(forServerPostId: serverPostId) else { return nil }
        let communityId = Lemmy.CommunityID(row.serverCommunityId)
        guard moderationCapability.canModerate(communityId: communityId) else { return nil }

        let postId = Lemmy.PostID(serverPostId)
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

    private func promptRemovePost(serverPostId: Lemmy.PostID) {
        presentModerationReasonAlert(
            title: NSLocalizedString("Remove post", comment: "Remove post dialog title"),
            message: NSLocalizedString("Optionally tell the author why the post was removed.", comment: "Remove post dialog message"),
            submitTitle: NSLocalizedString("Remove", comment: "Remove alert submit button")
        ) { [weak self] reason in
            self?.performRemovePost(serverPostId: serverPostId, removed: true, reason: reason)
        }
    }

    private func performRemovePost(
        serverPostId: Lemmy.PostID,
        removed: Bool,
        reason: String? = nil
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            Haptics.tap()
            do {
                try await viewModel.accountScope.lemmyService
                    .removePost(serverPostId: serverPostId, removed: removed, reason: reason)
                Haptics.success()
            } catch {
                alertService.handle(error, for: .removePost)
            }
        }
    }

    private func performLockPost(serverPostId: Lemmy.PostID, locked: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            Haptics.tap()
            do {
                try await viewModel.accountScope.lemmyService
                    .lockPost(serverPostId: serverPostId, locked: locked)
                Haptics.success()
            } catch {
                alertService.handle(error, for: .lockPost)
            }
        }
    }

    private func performFeaturePost(
        serverPostId: Lemmy.PostID,
        featured: Bool,
        local: Bool
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            Haptics.tap()
            do {
                try await viewModel.accountScope.lemmyService
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
    /// Prefetch at the same downsample size the cell fetches at, so the warmed
    /// entry is the one the cell (and the post-detail header's seed probe) reads.
    private static let thumbnailPrefetchSize = ImageService.feedThumbnailPointSize

    private func prefetchThumbnailUrls(for indexPaths: [IndexPath]) -> [URL] {
        let postContentDetector = dependencies.own.postContentDetectorService
        return indexPaths.compactMap { indexPath in
            guard case let .post(serverPostId) = dataSource.itemIdentifier(for: indexPath),
                  let row = viewModel.row(forServerPostId: serverPostId)
            else { return nil }
            return PostListPostViewModel.prefetchThumbnailUrl(for: row, postContentDetector: postContentDetector)
        }
    }

    /// Warms the image cache for image posts a few rows ahead of the visible
    /// window, so the thumbnail is already decoded by the time the cell is
    /// configured — no pop-in while scrolling quickly. The cell's own fetch then
    /// resolves from the cache. Text/link posts have nothing to prefetch.
    func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
        let urls = prefetchThumbnailUrls(for: indexPaths)
        guard !urls.isEmpty else { return }
        imageService.startPrefetching(urls, downsampleTo: Self.thumbnailPrefetchSize)
    }

    func tableView(_ tableView: UITableView, cancelPrefetchingForRowsAt indexPaths: [IndexPath]) {
        let urls = prefetchThumbnailUrls(for: indexPaths)
        guard !urls.isEmpty else { return }
        imageService.stopPrefetching(urls, downsampleTo: Self.thumbnailPrefetchSize)
    }
}
