//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import Observation
import OSLog
import SpudDataKit

private let logger = Logger.app

/// Drives the Inbox screen. Holds the active scope and, per scope, a phase and
/// the decoded results. Inbox content is transient (fetched on demand and held
/// in memory, like Search / Person content) - the durable signal is the
/// observable unread COUNT, owned by `UnreadCountService`.
@MainActor
@Observable
final class InboxViewModel {
    private static let pageLimit: Int64 = 50

    // MARK: Observable state

    var scope: InboxScope = .replies

    private(set) var repliesPhase: InboxPhase = .loading
    private(set) var mentionsPhase: InboxPhase = .loading
    private(set) var messagesPhase: InboxPhase = .loading

    private(set) var replies: [InboxReplyItem] = []
    private(set) var mentions: [InboxMentionItem] = []
    private(set) var conversations: [InboxConversation] = []

    /// True when the home instance's API doesn't support the inbox endpoints
    /// (Lemmy 1.0's v3 compat shim - see `InstanceCapability.inbox`). `loadAll()`
    /// skips every fetch in this state; the view controller shows an explanatory
    /// `UIContentUnavailableConfiguration` instead of an empty/error state.
    private(set) var isInboxGated = false
    /// The gated instance's host, for the capability-gate copy. Nil when
    /// `isInboxGated` is false, or when the instance host can't be resolved.
    private(set) var gatedHost: String?

    // MARK: Private

    @ObservationIgnored
    let isSignedIn: Bool

    @ObservationIgnored
    private let accountScope: AccountScope
    @ObservationIgnored
    private let appDatabase: AppDatabase
    @ObservationIgnored
    private let alertService: AlertServiceType
    @ObservationIgnored
    private let unreadCountService: UnreadCountServiceType
    @ObservationIgnored
    private let myPersonId: Lemmy.PersonID?
    /// Resolved once at init from `accountKeychainId`; nil when signed out / the
    /// account row isn't present. The conversation-list observations need it.
    @ObservationIgnored
    private let accountId: Int64?

    @ObservationIgnored
    private var repliesTask: Task<Void, Never>?
    @ObservationIgnored
    private var mentionsTask: Task<Void, Never>?
    /// One-shot server fetch + import for the messages scope (appear / refresh).
    @ObservationIgnored
    private var messagesFetchTask: Task<Void, Never>?
    /// Long-lived GRDB observation of the persisted conversation list.
    @ObservationIgnored
    private var conversationsObservationTask: Task<Void, Never>?
    /// Long-lived GRDB observation of pending outbound DMs across all recipients.
    @ObservationIgnored
    private var outboundObservationTask: Task<Void, Never>?

    /// Latest snapshot of confirmed conversations from `observeConversations`.
    @ObservationIgnored
    private var confirmedConversations: [PrivateMessageConversationRow] = []
    /// Latest snapshot of pending outbound DMs from `observeOutboundDirectMessages`.
    @ObservationIgnored
    private var outboundDMs: [OutboundContentRecord] = []
    /// True once the confirmed-conversations observation has emitted at least
    /// once, so the messages phase resolves the empty-vs-still-loading state
    /// honestly (the outbound observation can fire first).
    @ObservationIgnored
    private var hasReceivedConversations = false
    /// True once the conversation-list observations have been started, so a later
    /// `loadMessages` (refresh / re-appear) only re-fetches rather than spinning
    /// up duplicate observation tasks.
    @ObservationIgnored
    private var messagesObservationsStarted = false

    // MARK: Functions

    init(
        accountScope: AccountScope,
        appDatabase: AppDatabase,
        isSignedIn: Bool,
        myPersonId: Lemmy.PersonID?,
        alertService: AlertServiceType,
        unreadCountService: UnreadCountServiceType
    ) {
        self.accountScope = accountScope
        self.appDatabase = appDatabase
        self.isSignedIn = isSignedIn
        self.myPersonId = myPersonId
        self.alertService = alertService
        self.unreadCountService = unreadCountService
        accountId = appDatabase.accountRowIdSync(forKeychainId: accountScope.accountKeychainId)
    }

    deinit {
        repliesTask?.cancel()
        mentionsTask?.cancel()
        messagesFetchTask?.cancel()
        conversationsObservationTask?.cancel()
        outboundObservationTask?.cancel()
    }

    func scopeChanged(_ newScope: InboxScope) {
        guard newScope != scope else { return }
        scope = newScope
    }

    /// Loads (or reloads) every scope. Called on appear and on pull-to-refresh.
    /// Reads `accountScope.capabilities` once (it is a live per-access DB read;
    /// see the type's doc comment) and, when the instance doesn't support the
    /// inbox endpoints, skips all three fetches and exposes `isInboxGated` /
    /// `gatedHost` for the view controller's explain-don't-hide state instead.
    func loadAll() {
        guard isSignedIn else { return }
        let capabilities = accountScope.capabilities
        guard capabilities.can(.inbox) else {
            isInboxGated = true
            gatedHost = accountScope.instanceActorId?.hostWithPort
            // Nothing to fetch; resolve every scope to `.loaded` (empty) so the
            // view controller's phase switch doesn't get stuck showing the
            // initial `.loading` spinner - the gated content-unavailable state
            // takes over instead, checked ahead of the phase switch.
            repliesPhase = .loaded
            mentionsPhase = .loaded
            messagesPhase = .loaded
            return
        }
        isInboxGated = false
        gatedHost = nil
        loadReplies()
        loadMentions()
        loadMessages()
        Task { await unreadCountService.refresh(accountKeychainId: accountScope.accountKeychainId) }
    }

    /// The current instance capabilities, for view-controller-driven UI (e.g.
    /// hiding the compose button when private messages aren't supported).
    /// Resolves live like every other `accountScope` accessor - callers should
    /// read it once per render pass, not per cell.
    var capabilities: InstanceCapabilities {
        accountScope.capabilities
    }

    func loadReplies() {
        guard isSignedIn else { return }
        repliesTask?.cancel()
        repliesPhase = .loading
        repliesTask = Task { [weak self] in
            guard let self else { return }
            let service = accountScope.lemmyService
            do {
                let notifications = try await service.fetchReplies(unreadOnly: false, page: 1)
                if Task.isCancelled { return }
                replies = notifications.map(InboxReplyItem.init)
                repliesPhase = .loaded
            } catch {
                if Task.isCancelled { return }
                logger.error("Fetch replies failed: \(String(describing: error), privacy: .public)")
                alertService.handle(error, for: .fetchInbox)
                replies = []
                repliesPhase = .error
            }
        }
    }

    func loadMentions() {
        guard isSignedIn else { return }
        mentionsTask?.cancel()
        mentionsPhase = .loading
        mentionsTask = Task { [weak self] in
            guard let self else { return }
            let service = accountScope.lemmyService
            do {
                let notifications = try await service.fetchMentions(unreadOnly: false, page: 1)
                if Task.isCancelled { return }
                mentions = notifications.map(InboxMentionItem.init)
                mentionsPhase = .loaded
            } catch {
                if Task.isCancelled { return }
                logger.error("Fetch mentions failed: \(String(describing: error), privacy: .public)")
                alertService.handle(error, for: .fetchInbox)
                mentions = []
                mentionsPhase = .error
            }
        }
    }

    /// Drive the conversation list from GRDB (offline-readable) and an optimistic
    /// overlay of pending outbound DMs.
    ///
    /// The list is sourced from two long-lived observations (started once):
    /// `observeConversations` (the persisted source of truth) and
    /// `observeOutboundDirectMessages` (pending/sending/failed sends across all
    /// recipients). `InboxConversationMerger` combines them so an in-flight send
    /// shows a status indicator on its row and a brand-new conversation appears
    /// optimistically. Every `loadMessages` (appear / pull-to-refresh) ALSO kicks
    /// a one-shot server fetch that imports a fresh page into the store; the
    /// observation then re-emits with the updated rows. A failed fetch is
    /// non-fatal — already-persisted conversations keep rendering offline; only
    /// when there is genuinely nothing to show do we surface `.error`.
    func loadMessages() {
        guard isSignedIn else { return }
        guard accountId != nil else {
            // No account row resolved: nothing to observe. Render empty rather than
            // claiming an error (a signed-out / not-yet-imported account has no
            // conversations, and the empty state reads correctly).
            messagesPhase = .loaded
            return
        }
        // Stay in `.loading` until the first observation emission only on the very
        // first load; a refresh keeps the existing list visible.
        if !messagesObservationsStarted {
            messagesPhase = .loading
            startConversationsObservation()
            startOutboundDirectMessagesObservation()
            messagesObservationsStarted = true
        }
        refreshMessages()
    }

    /// One-shot server fetch + import; never blocks the observation-driven UI.
    private func refreshMessages() {
        guard let accountId else { return }
        messagesFetchTask?.cancel()
        messagesFetchTask = Task { [weak self] in
            guard let self else { return }
            let service = accountScope.lemmyService
            do {
                // Load the first page only; load-older paging is a later slice, so
                // the next cursor is intentionally discarded for now.
                let (messages, _) = try await service.fetchPrivateMessages(unreadOnly: false, pageCursor: nil)
                if Task.isCancelled { return }
                // upsert-only (a server page is partial), so nothing is deleted;
                // the conversation observation re-emits with the imported rows.
                try await appDatabase.upsertPrivateMessages(
                    messages,
                    accountId: accountId
                )
            } catch {
                if Task.isCancelled { return }
                logger.error("Fetch private messages failed: \(String(describing: error), privacy: .public)")
                // Degrade gracefully: only error out when there is nothing persisted
                // or pending to show. Otherwise the stale-but-present list keeps
                // rendering offline without a spurious error banner.
                if confirmedConversations.isEmpty, outboundDMs.isEmpty {
                    alertService.handle(error, for: .fetchInbox)
                    messagesPhase = .error
                }
            }
        }
    }

    private func startConversationsObservation() {
        guard let accountId else { return }
        conversationsObservationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await rows in appDatabase.observeConversations(accountId: accountId) {
                if Task.isCancelled { break }
                confirmedConversations = rows
                hasReceivedConversations = true
                recomputeConversations()
            }
        }
    }

    private func startOutboundDirectMessagesObservation() {
        let accountKeychainId = accountScope.accountKeychainId
        outboundObservationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await rows in appDatabase.observeOutboundDirectMessages(accountKeychainId: accountKeychainId) {
                if Task.isCancelled { break }
                outboundDMs = rows
                recomputeConversations()
            }
        }
    }

    /// Rebuild `conversations` by merging the two observation snapshots, then
    /// resolve the messages phase. Gated on `hasReceivedConversations` so the
    /// scope doesn't flash `.loaded` (empty/optimistic-only) before the persisted
    /// list has been read — mirroring `DMThreadViewModel.recompute`.
    private func recomputeConversations() {
        let accountKeychainId = accountScope.accountKeychainId
        conversations = InboxConversationMerger.merge(
            conversations: confirmedConversations,
            outboundDMs: outboundDMs,
            resolveCorrespondent: { [appDatabase] recipientServerPersonId in
                // One combined read per correspondent (name + avatar in a single
                // writer.read), not two — this runs on the @MainActor once per
                // correspondent on every observation tick.
                let resolved = appDatabase.personNameAndAvatarSync(
                    forKeychainId: accountKeychainId,
                    personId: recipientServerPersonId
                )
                return InboxConversationMerger.CorrespondentInfo(
                    name: resolved?.name,
                    avatarUrl: resolved?.avatarUrl.flatMap { URL(string: $0) }
                )
            }
        )

        // Two distinct invariants gate the promotion to `.loaded`:
        // (a) `hasReceivedConversations` — only promote once the persisted-
        //     conversations stream has emitted at least once. The outbound stream
        //     can fire first, and resolving `.loaded` off an optimistic-/empty-only
        //     snapshot would flash an empty list before the real rows are read.
        // (b) `messagesPhase != .error || !conversations.isEmpty` — do NOT overwrite
        //     an existing `.error` when there is nothing to display. This is the
        //     graceful-degradation path: a failed fetch with no persisted/pending
        //     content keeps the error visible rather than silently swapping it for
        //     an empty list (when there IS content, the error is irrelevant and we
        //     promote to `.loaded`).
        if hasReceivedConversations, messagesPhase != .error || !conversations.isEmpty {
            messagesPhase = .loaded
        }
    }

    // MARK: Mark read

    /// Mark a reply read (optimistically updates the row and the badge), then
    /// confirms with the server.
    func markReplyRead(_ item: InboxReplyItem) {
        guard isSignedIn, !item.isRead else { return }
        // Optimistic local update.
        replies = replies.map { $0.readReference == item.readReference ? $0.markedRead() : $0 }
        unreadCountService.decrement(replies: 1, mentions: 0, privateMessages: 0)

        Task { [weak self] in
            guard let self else { return }
            let service = accountScope.lemmyService
            do {
                try await service.markInboxItemAsRead(reference: item.readReference, read: true)
            } catch {
                logger.error("Mark reply read failed: \(String(describing: error), privacy: .public)")
                alertService.handle(error, for: .markInboxItemRead)
            }
        }
    }

    func markMentionRead(_ item: InboxMentionItem) {
        guard isSignedIn, !item.isRead else { return }
        mentions = mentions.map { $0.readReference == item.readReference ? $0.markedRead() : $0 }
        unreadCountService.decrement(replies: 0, mentions: 1, privateMessages: 0)

        Task { [weak self] in
            guard let self else { return }
            let service = accountScope.lemmyService
            do {
                try await service.markInboxItemAsRead(reference: item.readReference, read: true)
            } catch {
                logger.error("Mark mention read failed: \(String(describing: error), privacy: .public)")
                alertService.handle(error, for: .markInboxItemRead)
            }
        }
    }

    func markAllRead() {
        guard isSignedIn else { return }
        // Optimistic: clear everything locally and zero the badge.
        replies = replies.map { $0.markedRead() }
        mentions = mentions.map { $0.markedRead() }
        unreadCountService.reset()

        Task { [weak self] in
            guard let self else { return }
            let service = accountScope.lemmyService
            do {
                try await service.markAllInboxAsRead()
                // Reload to reflect the server's view (e.g. messages read state).
                await unreadCountService.refresh(accountKeychainId: accountScope.accountKeychainId)
            } catch {
                logger.error("Mark all inbox read failed: \(String(describing: error), privacy: .public)")
                alertService.handle(error, for: .markAllInboxRead)
            }
        }
    }
}
