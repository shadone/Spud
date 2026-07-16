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

    /// A stable scroll position: a specific message bubble and how far its top
    /// sits below the table's top content edge. Captured before older rows are
    /// prepended and restored after, so the visible messages don't jump.
    private struct ScrollAnchor {
        let itemId: DMBubbleItem.ID
        let distanceFromTop: CGFloat
    }

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

    /// Top-of-thread "Load earlier messages" control, installed as the table
    /// header while there is older history to fetch (see `updateLoadEarlierHeader`).
    private lazy var loadEarlierHeader = DMLoadEarlierHeaderView()

    // MARK: Functions

    init(
        accountKeychainId: String,
        correspondentId: Lemmy.PersonID,
        correspondentName: String,
        dependencies: Dependencies
    ) {
        let myPersonId = dependencies.appDatabase
            .accountOwnPersonIdsSync(forKeychainId: accountKeychainId)
            .map { Lemmy.PersonID($0.serverPersonId) }

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

        loadEarlierHeader.onTap = { [weak self] in
            self?.loadOlder()
        }
        // The delegate is only for `scrollViewDidScroll` (scroll-to-top load); row
        // sizing stays automatic (no `heightForRow`).
        tableView.delegate = self

        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // Read live at open time (no caching in the VC) - see AccountScope's
        // doc comment. When gated (the account's home instance doesn't
        // support private messages), skip the fetch/observation entirely -
        // `LemmyService`'s own calls would just reject anyway - and show the
        // explanatory state instead. `send(_:)` carries its own backstop for
        // a thread that was already open when the capability flipped (see its
        // doc comment), since this check only runs once, here, at open time.
        guard viewModel.accountScope.capabilities.can(.privateMessages) else {
            showGatedState()
            return
        }

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
                self?.handleBubblesChanged()
            }
        }
    }

    /// Apply the latest bubbles. A change that PREPENDS older history at the top
    /// (load-earlier) holds the reading position steady and applies without
    /// animation; every other change (initial load, a new incoming/optimistic
    /// message appended at the bottom) animates and scrolls to the bottom as
    /// before. The prepend-vs-append distinction is structural (see `isPrepend`),
    /// so no cross-call mode flag is needed and a late observation emit can't be
    /// misclassified.
    private func handleBubblesChanged() {
        let oldItems = dataSource.snapshot().itemIdentifiers
        let newItems = viewModel.bubbles
        let prepend = isPrepend(old: oldItems, new: newItems)

        // Reconcile the header's presence FIRST so its height is settled before we
        // capture/restore the scroll anchor — removing it after an anchor restore
        // would shift content by the header's height.
        updateLoadEarlierHeader()

        if prepend {
            let anchor = captureTopAnchor()
            applySnapshot(animated: false)
            if let anchor {
                restoreScrollAnchor(anchor)
            }
        } else {
            applySnapshot(animated: true)
            scrollToBottom(animated: true)
        }
    }

    /// True when `new` inserted at least one item ABOVE the previous first item —
    /// i.e. older history was prepended — as opposed to a new message appended at
    /// the bottom. The old top bubble's id is stable (a server message id doesn't
    /// change, and confirmations happen at the bottom), so its new index equals
    /// the number of prepended rows.
    private func isPrepend(old: [DMBubbleItem], new: [DMBubbleItem]) -> Bool {
        // Only a list already anchored by CONFIRMED history can be prepended. An
        // all-optimistic old list (a fast send before the first page loads) is the
        // pre-history state — its confirmed load must scroll to the bottom, not
        // anchor — so it is never treated as a prepend.
        guard let oldTop = old.first, !oldTop.isOptimistic,
              let newIndex = new.firstIndex(where: { $0.id == oldTop.id })
        else {
            return false
        }
        return newIndex > 0
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // The table header (a plain UIView) doesn't self-size; measure it once the
        // width is known and whenever it changes (rotation, split-view resize,
        // Dynamic Type). Guarded on an actual size delta so it never loops.
        sizeTableHeaderIfNeeded()
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
            // bubble height (mirrors the comment cell's re-layout). Snap without
            // animation so the image doesn't zoom in from a corner (see the
            // helper's doc).
            cell.onContentSizeChange = { [weak tableView] in
                tableView?.remeasureRowHeightsWithoutAnimation()
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

    /// Renders the terminal capability-gate state explaining that the
    /// account's home instance doesn't support private messages yet, and
    /// disables the input bar. Explain-don't-hide, matching the Inbox /
    /// Person-profile gated-state precedents: the thread stays reachable and
    /// this replaces `emptyConfiguration()` as the terminal state rather than
    /// stacking with it, since nothing is ever fetched to populate `bubbles`.
    private func showGatedState() {
        let host = viewModel.accountScope.instanceActorId?.hostWithPort
        let software = viewModel.accountScope.capabilities.software
        let copy = CapabilityGateCopy.copy(for: .privateMessages, host: host, software: software)
        var config = UIContentUnavailableConfiguration.empty()
        // `clock.badge.questionmark` matches every other capability-gate state
        // (Inbox, Person profile) - see those for the SF Symbol rationale.
        config.image = UIImage(systemName: "clock.badge.questionmark")
        config.text = copy.title
        config.secondaryText = copy.message
        contentUnavailableConfiguration = config

        inputBar.setComposeEnabled(false)
    }

    private func scrollToBottom(animated: Bool) {
        let count = viewModel.bubbles.count
        guard count > 0 else { return }
        let indexPath = IndexPath(row: count - 1, section: 0)
        tableView.scrollToRow(at: indexPath, at: .bottom, animated: animated)
    }

    // MARK: - Load earlier

    /// Kick off a load of older history. Triggered by the header button and by
    /// scrolling to the very top. Re-entrancy and the exhausted-history case are
    /// handled by the view model; the spinner is shown immediately so the tap
    /// feels responsive even before the async load sets `isLoadingOlder`.
    private func loadOlder() {
        guard !viewModel.isLoadingOlder, !viewModel.reachedHistoryStart else { return }
        loadEarlierHeader.setLoading(true)
        Task { @MainActor [weak self] in
            guard let self else { return }
            await viewModel.loadOlder()
            // The prepended rows arrive via the bubbles observation; reconcile the
            // header here too for the case where the load persisted nothing new
            // (no emit) — e.g. the cap was hit on already-seen pages.
            updateLoadEarlierHeader()
        }
    }

    /// Install / update / remove the "Load earlier" table header. Shown only when
    /// the thread has messages AND the overall history isn't exhausted; hidden
    /// once `reachedHistoryStart`. Toggles button↔spinner without changing height.
    private func updateLoadEarlierHeader() {
        // Show only once there is CONFIRMED history to page back through — never
        // above a lone optimistic (just-sent) bubble whose thread hasn't loaded its
        // first page yet: there is no cursor to page with, and it would also make
        // the first confirmed load look like a prepend (see `isPrepend`).
        let hasConfirmedHistory = viewModel.bubbles.contains { !$0.isOptimistic }
        let shouldShow = hasConfirmedHistory && !viewModel.reachedHistoryStart
        guard shouldShow else {
            removeLoadEarlierHeaderPreservingScroll()
            return
        }
        loadEarlierHeader.setLoading(viewModel.isLoadingOlder)
        if tableView.tableHeaderView !== loadEarlierHeader {
            tableView.tableHeaderView = loadEarlierHeader
        }
        sizeTableHeaderIfNeeded()
    }

    /// Remove the "Load earlier" header without jumping the visible messages. The
    /// header sits at the very top, so removing it shifts all content up by its
    /// height; counter that by pulling the content offset up the same amount
    /// (clamped to the top). This keeps the reading position steady whether the
    /// header is removed on its own — the final page yielded nothing for this
    /// thread, so no row prepend follows and no observation emit fires — or just
    /// before a prepend in `handleBubblesChanged`.
    private func removeLoadEarlierHeaderPreservingScroll() {
        guard let header = tableView.tableHeaderView else { return }
        let removedHeight = header.frame.height
        tableView.tableHeaderView = nil
        let minY = -tableView.adjustedContentInset.top
        tableView.contentOffset.y = max(tableView.contentOffset.y - removedHeight, minY)
    }

    /// A `tableHeaderView` (a plain UIView) must be given an explicit frame — it
    /// does not self-size from Auto Layout. Measure it against the table width and
    /// reassign only on an actual size change, so this is safe to call from
    /// `viewDidLayoutSubviews` without looping (and never reassigns mid-prepend,
    /// where the header height is constant).
    private func sizeTableHeaderIfNeeded() {
        guard let header = tableView.tableHeaderView else { return }
        let width = tableView.bounds.width
        guard width > 0 else { return }
        let target = header.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        if abs(header.frame.height - target.height) > 0.5 || header.frame.width != width {
            header.frame = CGRect(x: 0, y: 0, width: width, height: target.height)
            // Reassigning applies the new header height to the table's layout.
            tableView.tableHeaderView = header
        }
    }

    /// Capture the top-most visible message and its on-screen offset, so the same
    /// message can be pinned to the same position after older rows prepend above.
    private func captureTopAnchor() -> ScrollAnchor? {
        guard let indexPath = tableView.indexPathsForVisibleRows?.min(),
              let item = dataSource.itemIdentifier(for: indexPath)
        else {
            return nil
        }
        let rowRect = tableView.rectForRow(at: indexPath)
        let distanceFromTop = rowRect.minY - tableView.contentOffset.y
        return ScrollAnchor(itemId: item.id, distanceFromTop: distanceFromTop)
    }

    /// Restore a previously-captured anchor after a non-animated prepend: pin the
    /// anchored message back to its original on-screen offset so the newly-inserted
    /// older rows appear above without moving what the user was reading.
    private func restoreScrollAnchor(_ anchor: ScrollAnchor) {
        // Force the just-applied snapshot to lay out so `rectForRow` reflects the
        // new geometry (older rows now occupy space above the anchored row).
        tableView.layoutIfNeeded()
        guard let item = viewModel.bubbles.first(where: { $0.id == anchor.itemId }),
              let indexPath = dataSource.indexPath(for: item)
        else {
            return
        }
        let rowRect = tableView.rectForRow(at: indexPath)
        let targetY = max(rowRect.minY - anchor.distanceFromTop, -tableView.adjustedContentInset.top)
        tableView.setContentOffset(CGPoint(x: tableView.contentOffset.x, y: targetY), animated: false)
    }
}

// MARK: - UITableViewDelegate

extension DMThreadViewController: UITableViewDelegate {
    /// Trigger a load when the user pulls near the very top (older history is
    /// above). Gated to USER-initiated scrolls (`isDragging`/`isDecelerating`) so
    /// the programmatic anchor restore in `restoreScrollAnchor` never re-triggers
    /// a load, and to a loaded, non-empty, not-yet-exhausted thread. `loadOlder`'s
    /// own guards make repeat calls during a load inert.
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView.isDragging || scrollView.isDecelerating else { return }
        guard viewModel.phase == .loaded,
              !viewModel.bubbles.isEmpty,
              !viewModel.isLoadingOlder,
              !viewModel.reachedHistoryStart
        else {
            return
        }
        let topThreshold: CGFloat = 80
        if scrollView.contentOffset.y <= -scrollView.adjustedContentInset.top + topThreshold {
            loadOlder()
        }
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
        // Open in the browser per the app service (honors the in-app/Safari
        // preference), consistent with the rest of the app's external links.
        Task { [weak self] in
            guard let self else { return }
            await dependencies.own.appService.open(url: url, on: self)
        }
    }
}
