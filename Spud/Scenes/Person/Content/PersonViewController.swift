//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import OSLog
import SpudDataKit
import SpudUIKit
import SpudUtilKit
import UIKit

private let logger = Logger.app

/// The person profile content: an Apollo-style header pinned above a segmented
/// Posts / Comments list of the user's own content. Posts render as feed-style
/// rows and comments as comment-with-context rows (reusing the Search cells).
/// Tapping a post opens PostDetail; tapping a comment opens its post.
class PersonViewController: UIViewController {
    typealias OwnDependencies =
        HasAccountService &
        HasAlertService &
        HasAppDatabase &
        HasAppService &
        HasAppearanceService &
        HasImageService &
        HasPostContentDetectorService &
        HasPreferencesService
    /// Spelled out as a concrete protocol composition rather than the child
    /// VCs' `Dependencies` typealiases to avoid a recursive typealias cycle
    /// (Person -> Community -> PostList -> PostDetail -> Person). This is the
    /// union those expand to; the live `DependencyContainer` conforms to all.
    typealias NestedDependencies =
        HasAccountService &
        HasAlertService &
        HasAppDatabase &
        HasAppService &
        HasAppearanceService &
        HasDiagnosticLog &
        HasImageService &
        HasLinkEmbedService &
        HasNodeInfoService &
        HasPostContentDetectorService &
        HasPreferencesService &
        HasReachabilityMonitor &
        HasVoid
    typealias Dependencies = NestedDependencies & OwnDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    var accountService: AccountServiceType {
        dependencies.own.accountService
    }

    var alertService: AlertServiceType {
        dependencies.own.alertService
    }

    var imageService: ImageServiceType {
        dependencies.own.imageService
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

    var preferencesService: PreferencesServiceType {
        dependencies.own.preferencesService
    }

    var postContentDetector: PostContentDetectorServiceType {
        dependencies.own.postContentDetectorService
    }

    // MARK: Private

    private let accountKeychainId: String
    private let personRowId: Int64
    private let viewModel: PersonViewModel

    private let headerView = PersonHeaderView()

    /// Retained so the share sheet's iPad popover can anchor to it.
    private var overflowBarButtonItem: UIBarButtonItem?
    private var sortTypeBarButtonItem: UIBarButtonItem!
    private var sortTypeMenuActionsBySortType: [Lemmy.SortType: UIAction] = [:]

    private var headerObservationTask: Task<Void, Never>?
    private var contentObservationTask: Task<Void, Never>?
    private var statusObservationTask: Task<Void, Never>?
    private var bannerImageTask: Task<Void, Never>?
    private var avatarImageTask: Task<Void, Never>?
    private var loadedBannerUrl: URL?
    private var loadedAvatarUrl: URL?

    private enum Section: Hashable {
        case content
    }

    private enum Item: Hashable {
        /// Server-assigned post id (`PostListRow.serverPostId`), matching the
        /// feed's item identity so a GRDB re-emission reconfigures the cell in
        /// place (live vote / save / read state) rather than rebuilding the row.
        case post(serverPostId: Int64)
        case comment(SearchCommentResult)
    }

    /// The latest `PostListRow` per server post id, so the data source's cell
    /// provider can resolve a row from an `Item.post` identity. Mirrors the
    /// feed's `PostListViewController.rowsByServerPostId`.
    private var rowsByServerPostId: [Int64: PostListRow] = [:]

    /// Posts whose NSFW thumbnail the user revealed this session (by server post
    /// id). Not persisted; resets on relaunch. Mirrors the feed.
    private var revealedNsfwPostIds: Set<Int64> = []

    /// The post swipe-action config, sanitized for posts. Seeded from the
    /// preference (kept in lockstep on cell configure); drives the same vote /
    /// save / reply / share swipe actions as the feed.
    private var swipeActionConfig: SwipeActionConfig = .defaultPosts

    private lazy var segmentedControl: UISegmentedControl = {
        let control = UISegmentedControl(items: PersonContentTab.allCases.map(\.title))
        control.translatesAutoresizingMaskIntoConstraints = false
        control.selectedSegmentIndex = viewModel.tab.rawValue
        control.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
        return control
    }()

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 80
        tableView.delegate = self
        tableView.register(PostListPostCell.self, forCellReuseIdentifier: PostListPostCell.reuseIdentifier)
        tableView.register(SearchCommentCell.self, forCellReuseIdentifier: SearchCommentCell.reuseIdentifier)
        return tableView
    }()

    /// Wraps the profile header and the Posts / Comments tab control so they can
    /// be hosted as the table's `tableHeaderView` and scroll with the content
    /// (a tall bio in particular), rather than overflowing a fixed top region.
    private lazy var headerContainer: UIView = {
        let container = UIView()
        container.backgroundColor = Theme.background
        container.addSubview(headerView)
        container.addSubview(segmentedControl)
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: container.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            segmentedControl.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 8),
            segmentedControl.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            segmentedControl.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            segmentedControl.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
        ])
        return container
    }()

    private lazy var dataSource: UITableViewDiffableDataSource<Section, Item> = makeDataSource()

    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()

    private lazy var refreshControl: UIRefreshControl = {
        let control = UIRefreshControl()
        control.addTarget(self, action: #selector(refreshTriggered), for: .valueChanged)
        return control
    }()

    // MARK: Functions

    init(
        personRowId: Int64,
        serverPersonId: Lemmy.PersonID,
        accountKeychainId: String,
        dependencies: Dependencies,
        initialTab: PersonContentTab = .posts
    ) {
        self.dependencies = (own: dependencies, nested: dependencies)
        self.accountKeychainId = accountKeychainId
        self.personRowId = personRowId

        viewModel = PersonViewModel(
            personRowId: personRowId,
            serverPersonId: serverPersonId,
            accountScope: dependencies.accountService.scope(forAccountKeychainId: accountKeychainId),
            accountService: dependencies.accountService,
            appDatabase: dependencies.appDatabase,
            initialTab: initialTab
        )

        super.init(nibName: nil, bundle: nil)

        swipeActionConfig = dependencies.preferencesService
            .postSwipeActions
            .sanitized(for: .post)

        setup()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        headerObservationTask?.cancel()
        contentObservationTask?.cancel()
        statusObservationTask?.cancel()
        bannerImageTask?.cancel()
        avatarImageTask?.cancel()
    }

    private func setup() {
        view.backgroundColor = Theme.background

        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.imageService = imageService
        headerView.onBodyLinkTapped = { [weak self] url in
            self?.routeInternalLink(MarkdownInternalLink.resolve(url) ?? url)
        }
        headerView.onBodyImageTapped = { [weak self] url, altText, _ in
            guard let self else { return }
            presentMediaViewer(
                imageUrl: url,
                thumbnailUrl: nil,
                preloadedImage: nil,
                altText: altText,
                dependencies: dependencies.own
            )
        }
        headerView.onBodyVideoTapped = { [weak self] url in
            self?.presentVideoPlayer(url: url)
        }
        headerView.onBodyAudioTapped = { [weak self] url in
            self?.presentVideoPlayer(url: url)
        }
        // The header lives inside the table's `tableHeaderView`; when an inline
        // image loads and the bio grows, re-measure and commit the new header
        // height so the table can scroll the taller content.
        headerView.onBodyImageLoaded = { [weak self] in
            self?.layoutHeaderContainerIfNeeded()
        }
        headerView.onMatrixTapped = { matrix in
            Haptics.tap()
            UIPasteboard.general.string = matrix
        }

        tableView.refreshControl = refreshControl

        view.addSubview(tableView)
        view.addSubview(loadingIndicator)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            loadingIndicator.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),
        ])

        // Host the header + tab switcher as the table's self-sizing header so a
        // tall bio scrolls with the content instead of overflowing a fixed top
        // region (which clipped long bios with no way to scroll). The table
        // positions its header by frame, so opt the container out of Auto Layout
        // for its own frame while its subviews keep using constraints.
        headerContainer.translatesAutoresizingMaskIntoConstraints = true
        tableView.tableHeaderView = headerContainer

        let interaction = UIContextMenuInteraction(delegate: self)
        headerView.addInteraction(interaction)

        configureNavigationBar()
    }

    /// Builds the navbar: an overflow (`···`) menu and a sort button, in the
    /// same spirit as the Community screen. Both are always shown — sharing and
    /// sort need no sign-in; Message / Block live inside the overflow and only
    /// appear when signed in and viewing someone else's profile.
    private func configureNavigationBar() {
        setupSortTypeMenu()

        let shareGroup = UIMenu(options: .displayInline, children: [
            UIDeferredMenuElement.uncached { [weak self] completion in
                completion(self?.shareMenuActions() ?? [])
            },
        ])
        let userGroup = UIMenu(options: .displayInline, children: [
            UIDeferredMenuElement.uncached { [weak self] completion in
                completion(self?.userMenuActions() ?? [])
            },
        ])
        let overflowButton = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            menu: UIMenu(children: [shareGroup, userGroup])
        )
        overflowButton.accessibilityLabel = NSLocalizedString(
            "More",
            comment: "Person profile overflow menu accessibility label"
        )
        overflowBarButtonItem = overflowButton

        // Order (first element = right-most): overflow, then sort.
        navigationItem.rightBarButtonItems = [overflowButton, sortTypeBarButtonItem]
    }

    // MARK: Sort menu

    private func setupSortTypeMenu() {
        for sortType in PostSortMenu.all {
            let menuItem = sortType.itemForMenu
            let action = UIAction(title: menuItem.title, image: menuItem.image) { [weak self] _ in
                self?.sortTypeChanged(to: sortType)
            }
            sortTypeMenuActionsBySortType[sortType] = action
        }

        let button = UIBarButtonItem(
            title: "Sort type",
            image: UIImage(systemName: "line.horizontal.3.decrease.circle"),
            menu: nil
        )
        button.accessibilityLabel = NSLocalizedString(
            "Sort",
            comment: "Person profile sort menu accessibility label"
        )
        sortTypeBarButtonItem = button
        rebuildSortTypeMenu(activeSortType: viewModel.sortType)
    }

    private func rebuildSortTypeMenu(activeSortType: Lemmy.SortType) {
        for (sortType, action) in sortTypeMenuActionsBySortType {
            action.state = (sortType == activeSortType) ? .on : .off
        }
        sortTypeBarButtonItem.menu = UIMenu(
            title: "",
            options: .singleSelection,
            children: [
                UIMenu(title: "", options: .displayInline, children: PostSortMenu.actives.compactMap { sortTypeMenuActionsBySortType[$0] }),
                UIMenu(title: "Top", options: .singleSelection, children: PostSortMenu.tops.compactMap { sortTypeMenuActionsBySortType[$0] }),
                UIMenu(title: "", options: .displayInline, children: PostSortMenu.comments.compactMap { sortTypeMenuActionsBySortType[$0] }),
            ]
        )
    }

    private func sortTypeChanged(to sortType: Lemmy.SortType) {
        Haptics.tap()
        viewModel.changeSortType(sortType)
        rebuildSortTypeMenu(activeSortType: viewModel.sortType)
    }

    // MARK: Overflow menu

    /// Copy handle (always available) plus the URL-based sharing actions, which
    /// appear once the person's profile URL has resolved.
    private func shareMenuActions() -> [UIMenuElement] {
        let copyHandle = UIAction(
            title: NSLocalizedString("Copy handle", comment: "Overflow action to copy the @user@instance handle"),
            image: UIImage(systemName: "at")
        ) { [weak self] _ in
            Haptics.tap()
            UIPasteboard.general.string = self?.viewModel.handle
        }

        guard let url = viewModel.profileURL else { return [copyHandle] }

        let copyLink = UIAction(
            title: NSLocalizedString("Copy Link", comment: "Overflow action to copy a user's profile link"),
            image: UIImage(systemName: "doc.on.doc")
        ) { _ in
            Haptics.tap()
            UIPasteboard.general.url = url
        }
        let share = UIAction(
            title: NSLocalizedString("Share…", comment: "Overflow action to share a user's profile"),
            image: UIImage(systemName: "square.and.arrow.up")
        ) { [weak self] _ in
            self?.presentShareSheet(for: url, sourceItem: self?.overflowBarButtonItem)
        }
        let openInBrowser = UIAction(
            title: NSLocalizedString("Open in Browser", comment: "Overflow action to open a user's profile in the browser"),
            image: UIImage(systemName: "safari")
        ) { _ in
            Haptics.tap()
            UIApplication.shared.open(url)
        }
        return [copyHandle, copyLink, share, openInBrowser]
    }

    /// Message + Block / Unblock, shown only when signed in and viewing someone
    /// else's profile. Evaluated each time the menu opens so Block/Unblock
    /// reflects the latest state.
    private func userMenuActions() -> [UIMenuElement] {
        guard !viewModel.accountScope.isSignedOut, !isOwnProfile else { return [] }
        let message = UIAction(
            title: NSLocalizedString("Message", comment: "Overflow action to send a user a private message"),
            image: UIImage(systemName: "envelope")
        ) { [weak self] _ in
            self?.messageTapped()
        }
        return [message] + blockMenuActions()
    }

    /// Builds the Block / Unblock action for the overflow menu, reflecting the
    /// current `isBlocked` state.
    private func blockMenuActions() -> [UIMenuElement] {
        let blocked = viewModel.isBlocked
        let blockAction = UIAction(
            title: blocked
                ? NSLocalizedString("Unblock user", comment: "Overflow action to unblock a user")
                : NSLocalizedString("Block user", comment: "Overflow action to block a user"),
            image: UIImage(systemName: blocked ? "hand.raised.slash" : "hand.raised"),
            attributes: blocked ? [] : .destructive
        ) { [weak self] _ in
            self?.toggleBlockUser()
        }
        return [blockAction]
    }

    @objc
    private func messageTapped() {
        Haptics.tap()
        let composer = ComposerViewController.makeSheet(
            target: .privateMessage(recipientId: viewModel.serverPersonId),
            accountKeychainId: accountKeychainId,
            dependencies: dependencies.nested
        )
        present(composer, animated: true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        startObservations()
        viewModel.loadContent()
        // Resolve whether this person is already blocked so the context-menu
        // action shows the correct Block / Unblock label.
        if !isOwnProfile {
            viewModel.refreshBlockState()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateUserActivity()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        userActivity?.resignCurrent()
        userActivity = nil
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Size the table header against the current width (handles first layout
        // and rotation / size-class changes).
        layoutHeaderContainerIfNeeded()
    }

    /// Re-measures the table's header container against the current table width
    /// and commits its height so the table can scroll the full header (a tall
    /// bio in particular). Safe to call repeatedly: it only reassigns the
    /// `tableHeaderView` when the resolved height actually changes, so it does
    /// not loop with `viewDidLayoutSubviews`.
    private func layoutHeaderContainerIfNeeded() {
        let width = tableView.bounds.width
        guard width > 0 else { return }

        headerContainer.frame.size.width = width
        let height = headerContainer.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height

        guard abs(headerContainer.frame.height - height) > 0.5 else { return }
        headerContainer.frame.size.height = height
        // Reassigning is what makes the table adopt the new header height.
        tableView.tableHeaderView = headerContainer
    }

    /// Vends a Handoff/Spotlight/Prediction activity for this person, keyed by
    /// their canonical `ap_id` (resolved via the existing `.objectAtURL` path).
    private func updateUserActivity() {
        guard
            let actorIdString = appDatabase.personActorIdSync(forPersonRowId: personRowId),
            let actorURL = URL(string: actorIdString)
        else { return }
        let routingURL = URL.SpudInternalLink.objectAtURL(url: actorURL).url
        let activity = SpudUserActivity.viewPerson(routingURL: routingURL, handle: viewModel.handle)
        userActivity = activity
        activity.becomeCurrent()
    }

    /// True when this profile belongs to the backing account itself - block and
    /// message actions are suppressed for your own profile.
    private var isOwnProfile: Bool {
        guard !viewModel.accountScope.isSignedOut else { return false }
        let ownPersonId = appDatabase
            .accountOwnPersonIdsSync(forKeychainId: accountKeychainId)
            .map { Lemmy.PersonID($0.serverPersonId) }
        return ownPersonId == viewModel.serverPersonId
    }

    private func toggleBlockUser() {
        guard !viewModel.accountScope.isSignedOut else {
            presentSignInGate(
                title: NSLocalizedString("Sign in to block", comment: "Sign-in gate title when a signed-out user tries to block")
            )
            return
        }

        let blocking = !viewModel.isBlocked
        if blocking {
            presentDestructiveConfirmation(
                title: String(
                    format: NSLocalizedString("Block %@?", comment: "Block user confirmation title"),
                    viewModel.handle
                ),
                message: NSLocalizedString(
                    "You won't see posts or comments from this user. You can unblock them later.",
                    comment: "Block user confirmation message"
                ),
                confirmTitle: NSLocalizedString("Block", comment: "Block user confirm button"),
                sourceItem: navigationItem.rightBarButtonItem
            ) { [weak self] in
                Task { await self?.applyBlockUser(true) }
            }
        } else {
            Task { await applyBlockUser(false) }
        }
    }

    private func applyBlockUser(_ blocked: Bool) async {
        Haptics.tap()
        do {
            try await viewModel.setBlocked(blocked)
            Haptics.success()
        } catch {
            alertService.handle(error, for: .setBlockedPerson)
        }
    }

    // MARK: Observation

    private func startObservations() {
        headerObservationTask?.cancel()
        contentObservationTask?.cancel()
        statusObservationTask?.cancel()

        let viewModel = viewModel
        headerObservationTask = Task { @MainActor [weak self] in
            for await _ in ObservationStream.values(of: {
                (viewModel.title, viewModel.handle, viewModel.statsText, viewModel.bioMarkdown, viewModel.avatarUrl, viewModel.bannerUrl)
            }) {
                if Task.isCancelled { break }
                self?.applyHeader()
            }
        }
        statusObservationTask = Task { @MainActor [weak self] in
            for await _ in ObservationStream.values(of: {
                (viewModel.isBanned, viewModel.banExpires, viewModel.isDeleted, viewModel.isBotAccount, viewModel.isAdmin, viewModel.matrixUserId)
            }) {
                if Task.isCancelled { break }
                self?.applyHeader()
            }
        }
        contentObservationTask = Task { @MainActor [weak self] in
            for await _ in ObservationStream.values(of: {
                (viewModel.phase, viewModel.tab, viewModel.postRows, viewModel.content.comments)
            }) {
                if Task.isCancelled { break }
                self?.render()
            }
        }
    }

    private func applyHeader() {
        navigationItem.title = viewModel.title

        headerView.configure(
            title: viewModel.title,
            handle: viewModel.handle,
            statsText: viewModel.statsText,
            bioMarkdown: viewModel.bioMarkdown,
            status: PersonHeaderStatus(
                banText: viewModel.banStatusText,
                isDeleted: viewModel.isDeleted,
                isBot: viewModel.isBotAccount,
                isAdmin: viewModel.isAdmin,
                matrixUserId: viewModel.matrixUserId
            )
        )
        // The bio just changed, so the header's height may have changed; re-size
        // the table header to match (async markdown growth is handled by
        // `onBodyImageLoaded`).
        layoutHeaderContainerIfNeeded()

        loadBannerIfNeeded(url: viewModel.bannerUrl)
        loadAvatarIfNeeded(url: viewModel.avatarUrl)
    }

    private func loadBannerIfNeeded(url: URL?) {
        guard let url, url != loadedBannerUrl else { return }
        loadedBannerUrl = url
        bannerImageTask?.cancel()
        bannerImageTask = Task { [weak self] in
            for await state in self?.imageService.fetch(url) ?? .never {
                if Task.isCancelled { return }
                if case let .ready(image) = state {
                    self?.headerView.setBannerImage(image)
                }
            }
        }
    }

    private func loadAvatarIfNeeded(url: URL?) {
        guard let url, url != loadedAvatarUrl else { return }
        loadedAvatarUrl = url
        avatarImageTask?.cancel()
        avatarImageTask = Task { [weak self] in
            for await state in self?.imageService.fetch(url) ?? .never {
                if Task.isCancelled { return }
                if case let .ready(image) = state {
                    self?.headerView.setAvatarImage(image)
                }
            }
        }
    }

    // MARK: Rendering

    private func render() {
        switch viewModel.phase {
        case .loading:
            if !refreshControl.isRefreshing {
                loadingIndicator.startAnimating()
            }
            updateContentUnavailable(.none)
            applySnapshot([])
        case .loaded:
            loadingIndicator.stopAnimating()
            refreshControl.endRefreshing()
            applyContentSnapshot()
            updateContentUnavailable(
                viewModel.isEmpty(for: viewModel.tab) ? .empty : .none
            )
        case .error:
            loadingIndicator.stopAnimating()
            refreshControl.endRefreshing()
            applySnapshot([])
            updateContentUnavailable(.error)
        }
    }

    private func applyContentSnapshot() {
        let items: [Item]
        switch viewModel.tab {
        case .posts:
            // Keep the row map in lockstep with the snapshot so the cell
            // provider always resolves a `PostListRow` from an `Item.post`
            // identity (mirrors the feed's `apply(rows:)`).
            let rows = viewModel.postRows
            rowsByServerPostId = Dictionary(
                uniqueKeysWithValues: rows.map { ($0.serverPostId, $0) }
            )
            items = rows.map { Item.post(serverPostId: $0.serverPostId) }
        case .comments:
            rowsByServerPostId.removeAll()
            items = viewModel.content.comments.map(Item.comment)
        }
        applySnapshot(items)
    }

    private func applySnapshot(_ items: [Item]) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.content])
        snapshot.appendItems(items, toSection: .content)
        // A GRDB re-emission that only changes a post's data (vote, save, read)
        // keeps the same `serverPostId` identity, so reconfigure those cells in
        // place — otherwise a survived item's cell stays stale. Matches the
        // feed's `apply(rows:)`.
        snapshot.reconfigureItems(items)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private enum ContentUnavailable {
        case none
        case empty
        case error
    }

    private func updateContentUnavailable(_ state: ContentUnavailable) {
        // Render the empty/error state INSIDE the table's content area (its
        // `backgroundView`) rather than via the view-controller-level
        // `contentUnavailableConfiguration`, which overlays a content-unavailable
        // view across the WHOLE view (including the always-visible profile
        // header hosted as `tableView.tableHeaderView`) and so overlapped it.
        // The table fills the content region, so its background view centers
        // below the header and never collides with it; pull-to-refresh still
        // works because the header/refresh control are unaffected. Keep
        // `contentUnavailableConfiguration` nil so no lingering VC overlay
        // remains.
        switch state {
        case .none:
            tableView.backgroundView = nil
        case .empty:
            var config = UIContentUnavailableConfiguration.empty()
            switch viewModel.tab {
            case .posts:
                config.image = UIImage(systemName: "doc.richtext")
                config.text = NSLocalizedString("No posts", comment: "Person profile empty posts state")
                config.secondaryText = NSLocalizedString(
                    "This user hasn't posted anything yet.",
                    comment: "Person profile empty posts message"
                )
            case .comments:
                config.image = UIImage(systemName: "text.bubble")
                config.text = NSLocalizedString("No comments", comment: "Person profile empty comments state")
                config.secondaryText = NSLocalizedString(
                    "This user hasn't commented anywhere yet.",
                    comment: "Person profile empty comments message"
                )
            }
            tableView.backgroundView = config.makeContentView()
        case .error:
            var config = UIContentUnavailableConfiguration.empty()
            config.image = UIImage(systemName: "exclamationmark.triangle")
            config.text = NSLocalizedString("Couldn't load", comment: "Person profile error state title")
            config.secondaryText = NSLocalizedString(
                "Check your connection and pull to refresh.",
                comment: "Person profile error state message"
            )
            tableView.backgroundView = config.makeContentView()
        }
    }

    // MARK: Data source

    private func makeDataSource() -> UITableViewDiffableDataSource<Section, Item> {
        UITableViewDiffableDataSource<Section, Item>(tableView: tableView) { [weak self] tableView, indexPath, item in
            guard let self else { return UITableViewCell() }
            switch item {
            case let .post(serverPostId):
                return makePostCell(tableView, indexPath: indexPath, serverPostId: serverPostId)

            case let .comment(result):
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: SearchCommentCell.reuseIdentifier,
                    for: indexPath
                ) as! SearchCommentCell
                cell.configure(with: result)
                return cell
            }
        }
    }

    /// Configures a `PostListPostCell` for the person's post identified by
    /// `serverPostId`, mirroring the feed's cell provider: the same view model,
    /// the same callbacks (vote / media / link / reveal), so the row looks and
    /// behaves like a feed row.
    private func makePostCell(
        _ tableView: UITableView,
        indexPath: IndexPath,
        serverPostId: Int64
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: PostListPostCell.reuseIdentifier,
            for: indexPath
        ) as! PostListPostCell

        guard let row = rowsByServerPostId[serverPostId] else {
            logger.assertionFailure("Missing PostListRow for serverPostId \(serverPostId)")
            return cell
        }

        let cellViewModel = PostListPostViewModel(
            row: row,
            appearance: appearanceService,
            postContentDetector: postContentDetector,
            blurNsfw: preferencesService.blurNsfw,
            isRevealed: revealedNsfwPostIds.contains(serverPostId)
        )
        cell.configure(with: cellViewModel, imageService: imageService)

        cell.revealNsfwTapped = { [weak self] in
            guard let self else { return }
            revealedNsfwPostIds.insert(serverPostId)
            var snapshot = dataSource.snapshot()
            snapshot.reconfigureItems([.post(serverPostId: serverPostId)])
            dataSource.apply(snapshot, animatingDifferences: false)
        }

        cell.imageTapped = { [weak self] imageUrl, thumbnailUrl, thumbnailImage in
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

        cell.videoTapped = { [weak self] videoUrl in
            guard let self else { return }
            Task { await self.playVideo(url: videoUrl, appService: self.appService) }
        }

        cell.linkTapped = { [weak self] linkUrl in
            self?.openExternalLink(linkUrl)
        }

        cell.swipeActionConfiguration = swipeActionConfig.viewConfiguration(
            state: SwipeActionState(
                isSaved: row.isSaved,
                isUpvoted: row.voteStatus == 1,
                isDownvoted: row.voteStatus == 0
            ),
            appearance: appearanceService.general
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
    }

    // MARK: Post actions (feed parity)

    /// Dispatches a configured swipe action for a post. The save / vote paths go
    /// through the SAME per-account optimistic `LemmyService` calls the feed
    /// uses (the durable outbox), never a direct network write.
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

    /// Opens the composer to reply to the post (a top-level comment), gating on
    /// sign-in.
    private func replyToPost(serverPostId: Int64) {
        guard !viewModel.accountScope.isSignedOut else {
            presentSignInGate(
                title: NSLocalizedString("Sign in to comment", comment: "Sign-in gate title when a signed-out user tries to comment")
            )
            return
        }
        Haptics.tap()
        let composer = ComposerViewController.makeSheet(
            target: .postReply(serverPostId: Lemmy.PostID(serverPostId)),
            accountKeychainId: accountKeychainId,
            dependencies: dependencies.nested
        )
        present(composer, animated: true)
    }

    /// Shares the post's canonical URL, preferring its `ap_id` permalink.
    private func sharePost(serverPostId: Int64) {
        let instanceActorId = appDatabase.accountInstanceActorIdSync(
            forKeychainId: accountKeychainId
        )
        guard let url = LinkURL.forPost(
            instance: preferencesService.shareLinkInstance,
            originalPostUrl: rowsByServerPostId[serverPostId]?.originalPostUrl,
            serverPostId: serverPostId,
            instanceActorId: instanceActorId
        ) else {
            Haptics.warning()
            return
        }
        presentShareSheet(for: url, sourceView: view)
    }

    /// Opens an external-link post's url, honoring the user's "Open External
    /// Links in" preference.
    private func openExternalLink(_ url: URL) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await appService.open(url: url, on: self)
        }
    }

    // MARK: Actions

    @objc
    private func segmentChanged() {
        guard let tab = PersonContentTab(rawValue: segmentedControl.selectedSegmentIndex) else { return }
        Haptics.tap()
        viewModel.tabChanged(tab)
    }

    @objc
    private func refreshTriggered() {
        viewModel.loadContent()
    }
}

// MARK: - PostSaveDispatching

extension PersonViewController: PostSaveDispatching {
    var postActionsAccountScope: AccountScope {
        viewModel.accountScope
    }

    var postActionsAlertService: AlertServiceType {
        alertService
    }

    func currentSavedState(serverPostId: Int64) -> Bool {
        rowsByServerPostId[serverPostId]?.isSaved ?? false
    }
}

// MARK: - InternalLinkRouting

extension PersonViewController: InternalLinkRouting {
    var linkRouterAppDatabase: AppDatabase {
        appDatabase
    }

    var linkRouterLemmyService: LemmyServiceType {
        viewModel.accountScope.lemmyService
    }

    func routeToPerson(personId: Lemmy.PersonID, instance: InstanceActorId) {
        let vc = PersonOrLoadingViewController(
            personId: personId,
            instance: instance,
            accountKeychainId: accountKeychainId,
            dependencies: dependencies.nested
        )
        navigationController?.pushViewController(vc, animated: true)
    }

    func routeToCommunity(name: String, instance: InstanceActorId) {
        let vc = CommunityOrLoadingViewController(
            communityName: name,
            instance: instance,
            accountKeychainId: accountKeychainId,
            dependencies: dependencies.nested
        )
        navigationController?.pushViewController(vc, animated: true)
    }

    func routeToPost(postId: Lemmy.PostID, instance _: InstanceActorId) {
        guard let window = view.window as? MainWindow else {
            logger.error("No MainWindow available to display post")
            return
        }
        window.display(serverPostId: postId, accountKeychainId: accountKeychainId)
    }

    func routeToInstance(_ instance: InstanceActorId) {
        InstanceRouter.openInstance(
            host: instance.host,
            from: self,
            accountKeychainId: accountKeychainId,
            dependencies: dependencies.nested
        )
    }

    func routeToExternal(_ url: URL) {
        UIApplication.shared.open(url)
    }
}

// MARK: - UITableViewDelegate

extension PersonViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        guard let window = view.window as? MainWindow else { return }

        switch item {
        case let .post(serverPostId):
            window.display(
                serverPostId: Lemmy.PostID(serverPostId),
                accountKeychainId: accountKeychainId
            )
        case let .comment(result):
            window.display(serverPostId: result.serverPostId, accountKeychainId: accountKeychainId)
        }
    }
}

// MARK: - Context menu

extension PersonViewController: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(
        _: UIContextMenuInteraction,
        configurationForMenuAtLocation _: CGPoint
    ) -> UIContextMenuConfiguration? {
        UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }
            let copyHandle = UIAction(
                title: NSLocalizedString("Copy handle", comment: "Person header context-menu action to copy the @user@instance handle"),
                image: UIImage(systemName: "doc.on.doc")
            ) { [weak self] _ in
                UIPasteboard.general.string = self?.viewModel.handle
                Haptics.tap()
            }
            var children: [UIMenuElement] = [copyHandle]
            if !isOwnProfile {
                let blocked = viewModel.isBlocked
                let blockAction = UIAction(
                    title: blocked
                        ? NSLocalizedString("Unblock user", comment: "Context-menu action to unblock a user")
                        : NSLocalizedString("Block user", comment: "Context-menu action to block a user"),
                    image: UIImage(systemName: blocked ? "hand.raised.slash" : "hand.raised"),
                    attributes: blocked ? [] : .destructive
                ) { [weak self] _ in
                    self?.toggleBlockUser()
                }
                children.append(blockAction)
            }
            return UIMenu(title: "", children: children)
        }
    }
}

private extension AsyncStream {
    /// An empty stream, used as a fallback when `self` has already been
    /// deallocated by the time the image task starts.
    static var never: AsyncStream<Element> {
        AsyncStream { $0.finish() }
    }
}
