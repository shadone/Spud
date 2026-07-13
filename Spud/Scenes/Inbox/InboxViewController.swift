//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudDataKit
import SpudUIKit
import UIKit

/// The Inbox tab. A segmented control switches between Replies / Mentions /
/// Messages. Replies & mentions show the comment with post context, unread
/// items are visually distinct, tapping opens the comment's post in PostDetail
/// and marks it read; a swipe action and a "mark all read" button are
/// available. Messages shows a conversations list that drills into a DM thread.
final class InboxViewController: UIViewController {
    typealias OwnDependencies =
        HasAccountService &
        HasAlertService &
        HasAppDatabase &
        HasImageService &
        HasUnreadCountService
    /// Spelled out as a concrete composition to avoid recursive typealias
    /// cycles through the scene graph. The live `DependencyContainer` conforms.
    /// Includes `HasLinkEmbedService` because a DM thread pushed from here can in
    /// turn open a person/community/post screen whose comment bodies need it.
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
        HasUnreadCountService &
        HasVoid
    typealias Dependencies = NestedDependencies & OwnDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    private var imageService: ImageServiceType {
        dependencies.own.imageService
    }

    // MARK: Private

    private let accountKeychainId: String
    private let viewModel: InboxViewModel

    private var scopeObservationTask: Task<Void, Never>?
    private var dataObservationTask: Task<Void, Never>?

    private enum Section: Hashable { case items }

    private enum Item: Hashable {
        case reply(InboxReplyItem)
        case mention(InboxMentionItem)
        case conversation(InboxConversation)
        case reminder(ReminderListRow)
    }

    private lazy var segmentedControl: UISegmentedControl = {
        let control = UISegmentedControl(items: InboxScope.allCases.map(\.title))
        control.translatesAutoresizingMaskIntoConstraints = false
        control.selectedSegmentIndex = viewModel.scope.rawValue
        control.addTarget(self, action: #selector(scopeChanged), for: .valueChanged)
        return control
    }()

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 88
        tableView.delegate = self
        tableView.register(InboxCommentCell.self, forCellReuseIdentifier: InboxCommentCell.reuseIdentifier)
        tableView.register(InboxConversationCell.self, forCellReuseIdentifier: InboxConversationCell.reuseIdentifier)
        tableView.register(InboxReminderCell.self, forCellReuseIdentifier: InboxReminderCell.reuseIdentifier)
        return tableView
    }()

    private lazy var dataSource: UITableViewDiffableDataSource<Section, Item> = makeDataSource()

    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()

    /// Spinner shown as the table's footer while the Messages scope pages in more
    /// conversations (`viewModel.isLoadingMore`). Standard infinite-scroll bottom
    /// indicator — hidden in the other scopes and when there is nothing more to load.
    private let loadMoreSpinner = UIActivityIndicatorView(style: .medium)

    private lazy var loadMoreFooter: UIView = {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 44))
        loadMoreSpinner.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(loadMoreSpinner)
        NSLayoutConstraint.activate([
            loadMoreSpinner.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            loadMoreSpinner.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return container
    }()

    private lazy var refreshControl: UIRefreshControl = {
        let control = UIRefreshControl()
        control.addTarget(self, action: #selector(refreshTriggered), for: .valueChanged)
        return control
    }()

    private lazy var markAllReadButton = UIBarButtonItem(
        image: UIImage(systemName: "envelope.open"),
        style: .plain,
        target: self,
        action: #selector(markAllReadTapped)
    )

    /// Starts a new direct message. Shown only in the Messages scope (DMs are
    /// the only scope you can originate); hidden elsewhere and when signed out.
    private lazy var composeButton = UIBarButtonItem(
        systemItem: .compose,
        primaryAction: UIAction { [weak self] _ in self?.composeTapped() }
    )

    // MARK: Functions

    init(
        accountKeychainId: String,
        isSignedIn: Bool,
        dependencies: Dependencies
    ) {
        self.dependencies = (own: dependencies, nested: dependencies)
        self.accountKeychainId = accountKeychainId

        let myPersonId = dependencies.appDatabase
            .accountOwnPersonIdsSync(forKeychainId: accountKeychainId)
            .map { Lemmy.PersonID($0.serverPersonId) }

        viewModel = InboxViewModel(
            accountScope: dependencies.accountService.scope(forAccountKeychainId: accountKeychainId),
            appDatabase: dependencies.appDatabase,
            isSignedIn: isSignedIn,
            myPersonId: myPersonId,
            alertService: dependencies.alertService,
            unreadCountService: dependencies.unreadCountService
        )

        super.init(nibName: nil, bundle: nil)

        tabBarItem.title = NSLocalizedString("Inbox", comment: "Inbox tab title")
        tabBarItem.image = UIImage(systemName: "tray")
        tabBarItem.selectedImage = UIImage(systemName: "tray.fill")
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        scopeObservationTask?.cancel()
        dataObservationTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = Theme.background
        navigationItem.title = NSLocalizedString("Inbox", comment: "Inbox screen navigation title")

        markAllReadButton.accessibilityLabel = NSLocalizedString(
            "Mark all read",
            comment: "Inbox mark-all-read button accessibility label"
        )
        composeButton.accessibilityLabel = NSLocalizedString(
            "New message",
            comment: "Inbox compose-new-message button accessibility label"
        )
        // The actual bar-button set is scope/auth-driven and applied by render().

        view.addSubview(segmentedControl)
        view.addSubview(tableView)
        view.addSubview(loadingIndicator)

        tableView.refreshControl = refreshControl

        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            segmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            segmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            tableView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            loadingIndicator.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),
        ])

        startObservations()

        if viewModel.isSignedIn {
            viewModel.loadAll()
        } else {
            render()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Refresh on each appearance so newly-arrived items show and the badge
        // stays accurate without a full reload of every scope.
        if viewModel.isSignedIn, isMovingToParent == false {
            viewModel.loadAll()
        }
    }

    // MARK: Observation

    private func startObservations() {
        scopeObservationTask?.cancel()
        dataObservationTask?.cancel()

        let viewModel = viewModel
        scopeObservationTask = Task { @MainActor [weak self] in
            for await _ in ObservationStream.values(of: { viewModel.scope }) {
                if Task.isCancelled { break }
                self?.render()
            }
        }
        dataObservationTask = Task { @MainActor [weak self] in
            for await _ in ObservationStream.values(of: {
                (
                    viewModel.repliesPhase, viewModel.mentionsPhase, viewModel.messagesPhase,
                    viewModel.remindersPhase,
                    viewModel.replies, viewModel.mentions, viewModel.conversations,
                    viewModel.reminders,
                    viewModel.isLoadingMore
                )
            }) {
                if Task.isCancelled { break }
                self?.render()
            }
        }
    }

    // MARK: Rendering

    private var currentPhase: InboxPhase {
        switch viewModel.scope {
        case .replies: viewModel.repliesPhase
        case .mentions: viewModel.mentionsPhase
        case .messages: viewModel.messagesPhase
        case .reminders: viewModel.remindersPhase
        }
    }

    private var isCurrentScopeEmpty: Bool {
        switch viewModel.scope {
        case .replies: viewModel.replies.isEmpty
        case .mentions: viewModel.mentions.isEmpty
        case .messages: viewModel.conversations.isEmpty
        case .reminders: viewModel.reminders.isEmpty
        }
    }

    private func render() {
        updateNavigationItems()
        updateLoadMoreFooter()

        guard viewModel.isSignedIn else {
            loadingIndicator.stopAnimating()
            applySnapshot([])
            updateContentUnavailable(.signedOut)
            return
        }

        // Checked ahead of the phase switch: `loadAll()` resolves every scope
        // to `.loaded` (empty) when gated, since nothing was fetched - without
        // this check that would fall through to the ordinary `.empty` state
        // ("No replies" etc.) instead of explaining why the inbox is gated.
        // The Reminders scope is exempt: it's a purely local, durable feature
        // with no server dependency, so it renders normally even on an
        // instance whose Lemmy inbox endpoints are gated.
        guard !viewModel.isInboxGated || viewModel.scope == .reminders else {
            loadingIndicator.stopAnimating()
            refreshControl.endRefreshing()
            applySnapshot([])
            updateContentUnavailable(.gated)
            return
        }

        switch currentPhase {
        case .loading:
            if !refreshControl.isRefreshing {
                loadingIndicator.startAnimating()
            }
            updateContentUnavailable(.none)
        case .loaded:
            loadingIndicator.stopAnimating()
            refreshControl.endRefreshing()
            applyScopeSnapshot()
            updateContentUnavailable(isCurrentScopeEmpty ? .empty : .none)
        case .error:
            loadingIndicator.stopAnimating()
            refreshControl.endRefreshing()
            applySnapshot([])
            updateContentUnavailable(.error)
        }
    }

    /// Refreshes the navigation bar's right-hand buttons for the current scope
    /// and auth state. Compose (start a new DM) appears only in the Messages
    /// scope AND when the instance supports private messages; both buttons
    /// require a signed-in account (DMs and mark-all-read are account-tied),
    /// and both are hidden entirely when the inbox itself is gated (there is
    /// nothing to mark read, and a mark-all-read tap would just round-trip to
    /// a generic capability error). Driven from `render()`, which already
    /// fires on every scope change and on signed-out.
    private func updateNavigationItems() {
        guard viewModel.isSignedIn else {
            navigationItem.rightBarButtonItems = nil
            return
        }
        // Reminders have no "read" state (only "seen", auto-cleared on entering
        // the segment - see `InboxViewModel.scopeChanged`) and no compose action,
        // so neither bar button applies here.
        guard viewModel.scope != .reminders else {
            navigationItem.rightBarButtonItems = nil
            return
        }
        guard !viewModel.isInboxGated else {
            navigationItem.rightBarButtonItems = nil
            return
        }
        // Read once per render pass (a live per-access DB read) rather than
        // calling `.can(_:)` on separate accesses.
        let capabilities = viewModel.capabilities
        // Right-to-left ordering: mark-all-read sits at the trailing edge,
        // compose to its left, matching the existing single-button placement.
        navigationItem.rightBarButtonItems = viewModel.scope == .messages && capabilities.can(.privateMessages)
            ? [markAllReadButton, composeButton]
            : [markAllReadButton]
    }

    /// Shows or hides the bottom load-more spinner. Only the Messages scope pages
    /// (its conversation list walks the overall private-message list); the spinner
    /// appears while `viewModel.isLoadingMore` and is removed otherwise so it never
    /// lingers under a single-page replies/mentions list.
    private func updateLoadMoreFooter() {
        let shouldShow = viewModel.scope == .messages && viewModel.isLoadingMore
        if shouldShow {
            loadMoreSpinner.startAnimating()
            if tableView.tableFooterView !== loadMoreFooter {
                tableView.tableFooterView = loadMoreFooter
            }
        } else {
            loadMoreSpinner.stopAnimating()
            if tableView.tableFooterView === loadMoreFooter {
                tableView.tableFooterView = nil
            }
        }
    }

    private func applyScopeSnapshot() {
        let items: [Item]
        switch viewModel.scope {
        case .replies:
            items = viewModel.replies.map(Item.reply)
        case .mentions:
            items = viewModel.mentions.map(Item.mention)
        case .messages:
            items = viewModel.conversations.map(Item.conversation)
        case .reminders:
            items = viewModel.reminders.map(Item.reminder)
        }
        applySnapshot(items)
    }

    private func applySnapshot(_ items: [Item]) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.items])
        snapshot.appendItems(items, toSection: .items)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private enum ContentUnavailable {
        case none
        case empty
        case error
        case signedOut
        case gated
    }

    private func updateContentUnavailable(_ state: ContentUnavailable) {
        switch state {
        case .none:
            contentUnavailableConfiguration = nil
        case .empty:
            var config = UIContentUnavailableConfiguration.empty()
            switch viewModel.scope {
            case .replies:
                config.image = UIImage(systemName: "arrowshape.turn.up.left")
                config.text = NSLocalizedString("No replies", comment: "Inbox empty replies title")
                config.secondaryText = NSLocalizedString(
                    "Replies to your posts and comments show up here.",
                    comment: "Inbox empty replies message"
                )
            case .mentions:
                config.image = UIImage(systemName: "at")
                config.text = NSLocalizedString("No mentions", comment: "Inbox empty mentions title")
                config.secondaryText = NSLocalizedString(
                    "When someone @-mentions you, it shows up here.",
                    comment: "Inbox empty mentions message"
                )
            case .messages:
                config.image = UIImage(systemName: "envelope")
                config.text = NSLocalizedString("No messages", comment: "Inbox empty messages title")
                config.secondaryText = NSLocalizedString(
                    "Private conversations show up here.",
                    comment: "Inbox empty messages message"
                )
            case .reminders:
                config.image = UIImage(systemName: "bell")
                config.text = NSLocalizedString("No reminders", comment: "Inbox empty reminders title")
                config.secondaryText = NSLocalizedString(
                    "Set a reminder from a post's \u{201C}Remind Me\u{2026}\u{201D} menu and it shows up here.",
                    comment: "Inbox empty reminders message"
                )
            }
            contentUnavailableConfiguration = config
        case .error:
            var config = UIContentUnavailableConfiguration.empty()
            config.image = UIImage(systemName: "exclamationmark.triangle")
            config.text = NSLocalizedString("Couldn't load", comment: "Inbox error state title")
            config.secondaryText = NSLocalizedString(
                "Check your connection and pull to refresh.",
                comment: "Inbox error state message"
            )
            contentUnavailableConfiguration = config
        case .signedOut:
            var config = UIContentUnavailableConfiguration.empty()
            config.image = UIImage(systemName: "tray")
            config.text = NSLocalizedString("Sign in to use your inbox", comment: "Inbox signed-out title")
            config.secondaryText = NSLocalizedString(
                "Replies, mentions, and messages are tied to your account.",
                comment: "Inbox signed-out message"
            )
            contentUnavailableConfiguration = config
        case .gated:
            // Explain-don't-hide (design D6): the tab stays reachable and this
            // state explains why, for every scope - it isn't specific to
            // whichever segment happened to be selected.
            var config = UIContentUnavailableConfiguration.empty()
            let copy = CapabilityGateCopy.copy(for: .inbox, host: viewModel.gatedHost)
            // "tray.slash" doesn't exist as an SF Symbol (verified against this
            // SDK); `clock.badge.questionmark` reads as "not yet" - matching the
            // copy's "isn't available yet ... coming in an update" framing -
            // rather than a plain crossed-out tray.
            config.image = UIImage(systemName: "clock.badge.questionmark")
            config.text = copy.title
            config.secondaryText = copy.message
            contentUnavailableConfiguration = config
        }
    }

    // MARK: Data source

    private func makeDataSource() -> UITableViewDiffableDataSource<Section, Item> {
        UITableViewDiffableDataSource<Section, Item>(tableView: tableView) { [weak self] tableView, indexPath, item in
            guard let self else { return UITableViewCell() }
            switch item {
            case let .reply(reply):
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: InboxCommentCell.reuseIdentifier,
                    for: indexPath
                ) as! InboxCommentCell
                cell.configure(
                    creatorName: reply.creatorName,
                    content: reply.content,
                    postTitle: reply.postTitle,
                    communityName: reply.communityName,
                    isRead: reply.isRead
                )
                return cell

            case let .mention(mention):
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: InboxCommentCell.reuseIdentifier,
                    for: indexPath
                ) as! InboxCommentCell
                cell.configure(
                    creatorName: mention.creatorName,
                    content: mention.content,
                    postTitle: mention.postTitle,
                    communityName: mention.communityName,
                    isRead: mention.isRead
                )
                return cell

            case let .conversation(conversation):
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: InboxConversationCell.reuseIdentifier,
                    for: indexPath
                ) as! InboxConversationCell
                cell.configure(with: conversation, imageService: imageService)
                return cell

            case let .reminder(reminder):
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: InboxReminderCell.reuseIdentifier,
                    for: indexPath
                ) as! InboxReminderCell
                cell.configure(with: reminder, imageService: imageService)
                return cell
            }
        }
    }

    // MARK: Actions

    @objc
    private func scopeChanged() {
        guard let scope = InboxScope(rawValue: segmentedControl.selectedSegmentIndex) else { return }
        Haptics.tap()
        viewModel.scopeChanged(scope)
    }

    @objc
    private func refreshTriggered() {
        viewModel.loadAll()
    }

    @objc
    private func markAllReadTapped() {
        Haptics.success()
        viewModel.markAllRead()
    }

    /// Presents the modal "New message" recipient picker. On selection it opens a
    /// fresh DM thread with the chosen person — identical to the construction used
    /// when tapping an existing conversation row (`DMThreadViewController` renders a
    /// zero-message thread's empty state and accepts the first optimistic send).
    private func composeTapped() {
        Haptics.tap()
        let picker = RecipientPickerViewController(
            accountKeychainId: accountKeychainId,
            dependencies: dependencies.own
        )
        picker.onRecipientSelected = { [weak self] personId, name in
            self?.openNewThread(correspondentId: personId, correspondentName: name)
        }
        present(UINavigationController(rootViewController: picker), animated: true)
    }

    /// Pushes a new DM thread onto the inbox nav stack. The picker has already
    /// dismissed itself by the time this runs.
    private func openNewThread(
        correspondentId: Lemmy.PersonID,
        correspondentName: String
    ) {
        let threadVC = DMThreadViewController(
            accountKeychainId: accountKeychainId,
            correspondentId: correspondentId,
            correspondentName: correspondentName,
            dependencies: dependencies.nested
        )
        navigationController?.pushViewController(threadVC, animated: true)
    }

    private func openComment(serverPostId: Lemmy.PostID) {
        guard let window = view.window as? MainWindow else { return }
        window.display(serverPostId: serverPostId, accountKeychainId: accountKeychainId)
    }

    /// Opens a reminder's target post via the same `AppCoordinator` deep-link
    /// funnel every other system entry point uses, rather than `MainWindow`
    /// directly - a reminder's `apId` is a canonical ActivityPub URL (not a
    /// locally-known server post id, and possibly for a post whose local `post`
    /// cache row has since been evicted), so it routes through
    /// `.objectAtURL`'s `resolve_object` resolution rather than
    /// `window.display(serverPostId:)`.
    private func openReminder(_ reminder: ReminderListRow) {
        guard
            let window = view.window as? MainWindow,
            let apURL = URL(string: reminder.apId)
        else { return }
        let routingURL = URL.SpudInternalLink.objectAtURL(url: apURL).url
        AppCoordinator.shared.open(routingURL, in: window)
    }
}

// MARK: - UITableViewDelegate

extension InboxViewController: UITableViewDelegate {
    /// Infinite-scroll trigger for the Messages scope's conversation list. Fires
    /// `loadMore()` once the user scrolls into the last tenth of the content —
    /// mirroring `PostListViewController`'s threshold idiom. Only the Messages
    /// scope pages (replies/mentions are single-page). The view model guards
    /// re-entrancy / exhaustion / a missing cursor, so a repeated fire while a
    /// page is already in flight is a cheap no-op.
    ///
    /// Gated to USER-initiated scrolls (`isDragging`/`isDecelerating`), matching
    /// the DM thread: a page of the flat PM list can collapse into few new
    /// conversation rows, so without this gate a programmatic contentSize change
    /// near the bottom could re-fire and burst-page deep into history.
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard viewModel.scope == .messages else { return }
        guard scrollView.isDragging || scrollView.isDecelerating else { return }
        let position = scrollView.contentOffset.y + scrollView.bounds.height
        let totalHeight = scrollView.contentSize.height
        guard totalHeight > 0 else { return }
        if position / totalHeight > 0.9 {
            Task { [weak self] in await self?.viewModel.loadMore() }
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }

        switch item {
        case let .reply(reply):
            Haptics.tap()
            viewModel.markReplyRead(reply)
            openComment(serverPostId: reply.serverPostId)

        case let .mention(mention):
            Haptics.tap()
            viewModel.markMentionRead(mention)
            openComment(serverPostId: mention.serverPostId)

        case let .conversation(conversation):
            let threadVC = DMThreadViewController(
                accountKeychainId: accountKeychainId,
                correspondentId: conversation.correspondentId,
                correspondentName: conversation.correspondentName,
                dependencies: dependencies.nested
            )
            navigationController?.pushViewController(threadVC, animated: true)

        case let .reminder(reminder):
            Haptics.tap()
            openReminder(reminder)
        }
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return nil }

        switch item {
        case let .reply(reply):
            guard !reply.isRead else { return nil }
            return markReadSwipe { [weak self] in self?.viewModel.markReplyRead(reply) }
        case let .mention(mention):
            guard !mention.isRead else { return nil }
            return markReadSwipe { [weak self] in self?.viewModel.markMentionRead(mention) }
        case .conversation:
            return nil
        case let .reminder(reminder):
            return removeReminderSwipe { [weak self] in self?.viewModel.removeReminder(reminder) }
        }
    }

    private func markReadSwipe(_ action: @escaping () -> Void) -> UISwipeActionsConfiguration {
        let markRead = UIContextualAction(
            style: .normal,
            title: NSLocalizedString("Read", comment: "Inbox swipe action: mark read")
        ) { _, _, completion in
            Haptics.tap()
            action()
            completion(true)
        }
        markRead.backgroundColor = .systemBlue
        markRead.image = UIImage(systemName: "envelope.open")
        return UISwipeActionsConfiguration(actions: [markRead])
    }

    /// Destructive swipe to cancel a reminder (Reminders segment only) - mirrors
    /// `markReadSwipe`'s shape but removes the row rather than marking it read.
    private func removeReminderSwipe(_ action: @escaping () -> Void) -> UISwipeActionsConfiguration {
        let remove = UIContextualAction(
            style: .destructive,
            title: NSLocalizedString("Remove", comment: "Inbox swipe action: remove a reminder")
        ) { _, _, completion in
            Haptics.tap()
            action()
            completion(true)
        }
        remove.image = UIImage(systemName: "bell.slash")
        return UISwipeActionsConfiguration(actions: [remove])
    }
}
