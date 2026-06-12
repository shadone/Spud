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
    typealias NestedDependencies =
        HasAccountService &
        HasAlertService &
        HasAppDatabase &
        HasAppService &
        HasAppearanceService &
        HasImageService &
        HasPostContentDetectorService &
        HasPreferencesService &
        HasUnreadCountService &
        HasVoid
    typealias Dependencies = NestedDependencies & OwnDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    private var accountService: AccountServiceType {
        dependencies.own.accountService
    }

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
        return tableView
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

    private lazy var markAllReadButton = UIBarButtonItem(
        image: UIImage(systemName: "envelope.open"),
        style: .plain,
        target: self,
        action: #selector(markAllReadTapped)
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
            .map { Components.Schemas.PersonID($0.serverPersonId) }

        viewModel = InboxViewModel(
            accountKeychainId: accountKeychainId,
            isSignedIn: isSignedIn,
            myPersonId: myPersonId,
            accountService: dependencies.accountService,
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

        view.backgroundColor = .systemBackground
        navigationItem.title = NSLocalizedString("Inbox", comment: "Inbox screen navigation title")

        if viewModel.isSignedIn {
            navigationItem.rightBarButtonItem = markAllReadButton
            markAllReadButton.accessibilityLabel = NSLocalizedString(
                "Mark all read",
                comment: "Inbox mark-all-read button accessibility label"
            )
        }

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
                    viewModel.replies, viewModel.mentions, viewModel.conversations
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
        }
    }

    private var isCurrentScopeEmpty: Bool {
        switch viewModel.scope {
        case .replies: viewModel.replies.isEmpty
        case .mentions: viewModel.mentions.isEmpty
        case .messages: viewModel.conversations.isEmpty
        }
    }

    private func render() {
        guard viewModel.isSignedIn else {
            loadingIndicator.stopAnimating()
            applySnapshot([])
            updateContentUnavailable(.signedOut)
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

    private func applyScopeSnapshot() {
        let items: [Item]
        switch viewModel.scope {
        case .replies:
            items = viewModel.replies.map(Item.reply)
        case .mentions:
            items = viewModel.mentions.map(Item.mention)
        case .messages:
            items = viewModel.conversations.map(Item.conversation)
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

    private func openComment(serverPostId: Components.Schemas.PostID) {
        guard let window = view.window as? MainWindow else { return }
        window.display(serverPostId: serverPostId, accountKeychainId: accountKeychainId)
    }
}

// MARK: - UITableViewDelegate

extension InboxViewController: UITableViewDelegate {
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
                initialMessages: conversation.messages,
                dependencies: dependencies.nested
            )
            navigationController?.pushViewController(threadVC, animated: true)
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
}
