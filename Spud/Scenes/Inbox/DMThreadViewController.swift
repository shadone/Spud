//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
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

/// A chat-style DM thread: messages rendered as left/right bubbles with an
/// inline compose bar pinned to the keyboard. GRDB-backed and optimistic —
/// sending posts via `LemmyService.sendDirectMessage` (durable composer outbox)
/// and the optimistic bubble appears instantly from the outbound observation,
/// merged with the persisted confirmed messages by `DMThreadViewModel`.
final class DMThreadViewController: UIViewController {
    /// What this screen needs directly: services for its own view model plus the
    /// image service (DM bodies render Markdown, which may carry an inline image)
    /// and the app service (opening a tapped web link in the browser).
    typealias OwnDependencies =
        HasAccountService &
        HasAlertService &
        HasAppDatabase &
        HasAppService &
        HasImageService &
        HasUnreadCountService
    /// What the screens a tapped body link pushes onto the nav stack need. Spelled
    /// out as the concrete union (rather than their `Dependencies` typealiases) to
    /// avoid a recursive typealias cycle, mirroring `PersonViewController`.
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

    /// The account this thread belongs to, retained so body-link routing can open
    /// the linked person/community/post under the same account.
    let accountKeychainId: String

    private let viewModel: DMThreadViewModel

    private var bubblesObservationTask: Task<Void, Never>?

    /// Tracks whether `viewDidAppear` has fired at least once. The FIRST appear is
    /// a no-op for mark-read because `start()` (in `viewDidLoad`) already marks the
    /// thread read via `refresh(markRead:)`; subsequent appears (returning to an
    /// already-loaded thread that received new messages while backgrounded /
    /// pushed-over) drive `markReadOnOpen()`, which the load path no longer covers.
    private var hasAppearedOnce = false

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

    private lazy var dataSource: UITableViewDiffableDataSource<Section, DMBubbleItem> = makeDataSource()

    private lazy var inputBar = DMInputBar()

    // MARK: Functions

    init(
        accountKeychainId: String,
        correspondentId: Components.Schemas.PersonID,
        correspondentName: String,
        dependencies: Dependencies
    ) {
        let myPersonId = dependencies.appDatabase
            .accountOwnPersonIdsSync(forKeychainId: accountKeychainId)
            .map { Components.Schemas.PersonID($0.serverPersonId) }

        self.dependencies = (own: dependencies, nested: dependencies)
        self.accountKeychainId = accountKeychainId

        viewModel = DMThreadViewModel(
            accountScope: dependencies.accountService.scope(forAccountKeychainId: accountKeychainId),
            appDatabase: dependencies.appDatabase,
            correspondentId: correspondentId,
            correspondentName: correspondentName,
            myPersonId: myPersonId,
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
        bubblesObservationTask?.cancel()
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
            // Clear the saved draft now that the text has been sent.
            self?.viewModel.autosaveDraft("")
        }
        inputBar.textChanged = { [weak self] text in
            self?.viewModel.autosaveDraft(text)
        }

        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        startObservation()
        viewModel.start()
        restoreDraft()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        scrollToBottom(animated: false)
        // First appear is already covered by start()'s refresh(markRead:); only
        // re-appears (returning to a thread that gained messages meanwhile) need an
        // explicit mark-read. markCorrespondentMessagesRead is idempotent and only
        // decrements the badge by the count actually marked, so no double-decrement.
        if hasAppearedOnce {
            viewModel.markReadOnOpen()
        } else {
            hasAppearedOnce = true
        }
    }

    private func startObservation() {
        let viewModel = viewModel
        bubblesObservationTask = Task { @MainActor [weak self] in
            for await _ in ObservationStream.values(of: { viewModel.bubbles }) {
                if Task.isCancelled { break }
                self?.applySnapshot(animated: true)
                self?.scrollToBottom(animated: true)
            }
        }
    }

    /// Restore the per-recipient draft into the input bar on open, unless the
    /// user has already started typing (a fast typer beating the async load).
    private func restoreDraft() {
        Task { @MainActor [weak self] in
            guard let self, let draft = await viewModel.loadDraft() else { return }
            // A fast typer can beat the async draft load; never overwrite text the
            // user already started entering.
            guard inputBar.isEmpty else { return }
            inputBar.setText(draft)
        }
    }

    private func makeDataSource() -> UITableViewDiffableDataSource<Section, DMBubbleItem> {
        UITableViewDiffableDataSource<Section, DMBubbleItem>(tableView: tableView) { [weak self] tableView, indexPath, item in
            let cell = tableView.dequeueReusableCell(
                withIdentifier: DMBubbleCell.reuseIdentifier,
                for: indexPath
            ) as! DMBubbleCell
            guard let self else { return cell }
            cell.configure(with: item, imageService: dependencies.own.imageService)
            // Route a tapped body-text link the same way the post/comment body
            // does: resolve a `spud-markdown://` link to the internal URL, then
            // dispatch through the shared InternalLinkRouting.
            cell.onLinkTapped = { [weak self] url in
                self?.routeInternalLink(MarkdownInternalLink.resolve(url) ?? url)
            }
            // Re-measure the row when an inline body image loads and changes the
            // bubble height (mirrors the comment cell's re-layout).
            cell.onContentSizeChange = { [weak tableView] in
                tableView?.performBatchUpdates(nil)
            }
            // Wire the failed-state tap to the Retry / Discard sheet.
            if item.pendingStatus == .failed, let token = item.clientToken {
                cell.onFailedTap = { [weak self] in
                    self?.presentFailedActions(clientToken: token, body: item.content)
                }
            }
            return cell
        }
    }

    private func applySnapshot(animated: Bool) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, DMBubbleItem>()
        snapshot.appendSections([.messages])
        snapshot.appendItems(viewModel.bubbles, toSection: .messages)
        // Reconfigure existing items so a sending -> failed transition (same
        // synthetic id) re-renders the bubble's status without a remove/insert.
        // Only items ALREADY in the current data-source snapshot may be
        // reconfigured — passing a brand-new (just-appended) item trips a debug
        // assertion on some iOS versions — so intersect against what's live.
        let existing = Set(dataSource.snapshot().itemIdentifiers)
        snapshot.reconfigureItems(viewModel.bubbles.filter { $0.isOptimistic && existing.contains($0) })
        dataSource.apply(snapshot, animatingDifferences: animated)

        contentUnavailableConfiguration = viewModel.bubbles.isEmpty ? emptyConfiguration() : nil
    }

    /// Presents the Retry / Discard action sheet for a failed optimistic send.
    /// Mirrors the post-detail pending-comment failed tap handler.
    private func presentFailedActions(clientToken: String, body: String) {
        Haptics.tap()
        let sheet = UIAlertController(
            title: NSLocalizedString("Message not delivered", comment: "Failed DM action sheet title"),
            message: body,
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(
            title: NSLocalizedString("Retry", comment: "Retry a failed DM send"),
            style: .default
        ) { [weak self] _ in
            self?.viewModel.retry(clientToken: clientToken)
        })
        sheet.addAction(UIAlertAction(
            title: NSLocalizedString("Discard", comment: "Discard a failed DM send"),
            style: .destructive
        ) { [weak self] _ in
            self?.viewModel.discard(clientToken: clientToken)
        })
        sheet.addAction(UIAlertAction(
            title: NSLocalizedString("Cancel", comment: "Cancel the failed DM action sheet"),
            style: .cancel
        ))

        // iPad: anchor the popover to the failed bubble's cell.
        if let popover = sheet.popoverPresentationController {
            if let item = viewModel.bubbles.first(where: { $0.clientToken == clientToken }),
               let indexPath = dataSource.indexPath(for: item),
               let cell = tableView.cellForRow(at: indexPath)
            {
                popover.sourceView = cell
                popover.sourceRect = cell.bounds
            } else {
                popover.sourceView = view
                popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
        }
        present(sheet, animated: true)
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
        let count = viewModel.bubbles.count
        guard count > 0 else { return }
        let indexPath = IndexPath(row: count - 1, section: 0)
        tableView.scrollToRow(at: indexPath, at: .bottom, animated: animated)
    }
}

// MARK: - InternalLinkRouting

/// Routes a tapped DM body-text link exactly as the post/comment bodies do: a
/// mention/community/post resolves and pushes in-app onto the thread's nav stack;
/// an unrecognized web URL opens in the browser.
extension DMThreadViewController: InternalLinkRouting {
    var linkRouterAppDatabase: AppDatabase {
        dependencies.own.appDatabase
    }

    var linkRouterLemmyService: LemmyServiceType {
        viewModel.accountScope.lemmyService
    }

    func routeToPerson(personId: Components.Schemas.PersonID, instance: InstanceActorId) {
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

    func routeToPost(postId: Components.Schemas.PostID, instance _: InstanceActorId) {
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
        // Open in the browser per the app service (honors the in-app/Safari
        // preference), consistent with the rest of the app's external links.
        Task { [weak self] in
            guard let self else { return }
            await dependencies.own.appService.open(url: url, on: self)
        }
    }
}
