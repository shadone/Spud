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

/// A chat-style DM thread: messages rendered as left/right bubbles with an
/// inline compose bar pinned to the keyboard. Sending posts via
/// `LemmyService.sendPrivateMessage` (the same path the composer sheet uses).
final class DMThreadViewController: UIViewController {
    typealias Dependencies =
        HasAccountService &
        HasAlertService &
        HasAppDatabase &
        HasUnreadCountService

    private let viewModel: DMThreadViewModel

    private var messagesObservationTask: Task<Void, Never>?
    private var sendingObservationTask: Task<Void, Never>?

    private enum Section: Hashable { case messages }

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60
        tableView.separatorStyle = .none
        tableView.keyboardDismissMode = .interactive
        tableView.allowsSelection = false
        tableView.register(DMBubbleCell.self, forCellReuseIdentifier: DMBubbleCell.reuseIdentifier)
        return tableView
    }()

    private lazy var dataSource: UITableViewDiffableDataSource<Section, InboxMessageItem> = makeDataSource()

    private lazy var inputBar = DMInputBar()

    // MARK: Functions

    init(
        accountKeychainId: String,
        correspondentId: Components.Schemas.PersonID,
        correspondentName: String,
        initialMessages: [InboxMessageItem],
        dependencies: Dependencies
    ) {
        let myPersonId = dependencies.appDatabase
            .accountOwnPersonIdsSync(forKeychainId: accountKeychainId)
            .map { Components.Schemas.PersonID($0.serverPersonId) }

        viewModel = DMThreadViewModel(
            accountScope: dependencies.accountService.scope(forAccountKeychainId: accountKeychainId),
            correspondentId: correspondentId,
            correspondentName: correspondentName,
            myPersonId: myPersonId,
            initialMessages: initialMessages,
            alertService: dependencies.alertService,
            unreadCountService: dependencies.unreadCountService
        )

        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        messagesObservationTask?.cancel()
        sendingObservationTask?.cancel()
    }

    override var canBecomeFirstResponder: Bool {
        true
    }

    override var inputAccessoryView: UIView? {
        inputBar
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        navigationItem.title = viewModel.correspondentName

        inputBar.sendTapped = { [weak self] text in
            Haptics.tap()
            self?.viewModel.send(text)
            self?.inputBar.clear()
        }

        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        startObservations()
        applySnapshot(animated: false)
        viewModel.markReadOnOpen()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        scrollToBottom(animated: false)
    }

    private func startObservations() {
        let viewModel = viewModel
        messagesObservationTask = Task { @MainActor [weak self] in
            for await _ in ObservationStream.values(of: { viewModel.messages }) {
                if Task.isCancelled { break }
                self?.applySnapshot(animated: true)
                self?.scrollToBottom(animated: true)
            }
        }
        sendingObservationTask = Task { @MainActor [weak self] in
            for await sending in ObservationStream.values(of: { viewModel.isSending }) {
                if Task.isCancelled { break }
                self?.inputBar.setSending(sending)
            }
        }
    }

    private func makeDataSource() -> UITableViewDiffableDataSource<Section, InboxMessageItem> {
        UITableViewDiffableDataSource<Section, InboxMessageItem>(tableView: tableView) { [weak self] tableView, indexPath, message in
            let cell = tableView.dequeueReusableCell(
                withIdentifier: DMBubbleCell.reuseIdentifier,
                for: indexPath
            ) as! DMBubbleCell
            let outgoing = self?.viewModel.isOutgoing(message) ?? false
            cell.configure(text: message.content, outgoing: outgoing)
            return cell
        }
    }

    private func applySnapshot(animated: Bool) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, InboxMessageItem>()
        snapshot.appendSections([.messages])
        snapshot.appendItems(viewModel.messages, toSection: .messages)
        dataSource.apply(snapshot, animatingDifferences: animated)

        contentUnavailableConfiguration = viewModel.messages.isEmpty ? emptyConfiguration() : nil
    }

    private func emptyConfiguration() -> UIContentUnavailableConfiguration {
        var config = UIContentUnavailableConfiguration.empty()
        config.image = UIImage(systemName: "bubble.left.and.bubble.right")
        config.text = NSLocalizedString("No messages yet", comment: "DM thread empty state title")
        config.secondaryText = NSLocalizedString(
            "Say hello to start the conversation.",
            comment: "DM thread empty state message"
        )
        return config
    }

    private func scrollToBottom(animated: Bool) {
        let count = viewModel.messages.count
        guard count > 0 else { return }
        let indexPath = IndexPath(row: count - 1, section: 0)
        tableView.scrollToRow(at: indexPath, at: .bottom, animated: animated)
    }
}
