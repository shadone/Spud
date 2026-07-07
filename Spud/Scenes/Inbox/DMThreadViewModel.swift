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

/// Drives a single DM thread (chat-style), GRDB-backed with optimistic, durable
/// sends.
///
/// The rendered `bubbles` are a MERGE of two observations:
/// 1. `observeMessages` — confirmed messages persisted in the `privateMessage`
///    store (the source of truth, refreshed by importing a server fetch).
/// 2. `observeOutboundDMs` — still pending/sending/failed outbound rows from the
///    composer outbox (`ComposerOutboxService`).
///
/// Sending is fire-and-forget: `send(_:)` calls `sendDirectMessage`, which
/// returns immediately after a fast DB write and drains the network on a
/// detached task. The optimistic bubble appears from the outbound observation —
/// the VM never awaits the send, so several messages can be in flight at once
/// and the UI stays instant. On success the performer imports the confirmed
/// message and the generic outbox path deletes the outbound row; the merge's
/// dedup window (see `recompute`) hides the optimistic bubble for the brief
/// instant both coexist, so there is no duplicate-bubble flash.
@MainActor
@Observable
final class DMThreadViewModel {
    // MARK: Observable state

    /// The merged, render-ready bubbles in chat order (oldest first).
    private(set) var bubbles: [DMBubbleItem] = []
    private(set) var phase: InboxPhase = .loading

    let correspondentId: Components.Schemas.PersonID
    let correspondentName: String

    // MARK: Private

    @ObservationIgnored
    let accountScope: AccountScope
    @ObservationIgnored
    private let appDatabase: AppDatabase
    @ObservationIgnored
    private let accountId: Int64?
    @ObservationIgnored
    private let myServerPersonId: Int64?
    @ObservationIgnored
    private let alertService: AlertServiceType
    @ObservationIgnored
    private let unreadCountService: UnreadCountServiceType

    /// Latest snapshot of confirmed messages from `observeMessages`.
    @ObservationIgnored
    private var confirmedMessages: [PrivateMessageRow] = []
    /// Latest snapshot of pending/failed outbound sends from `observeOutboundDMs`.
    @ObservationIgnored
    private var outboundRows: [OutboundContentRecord] = []
    /// True once at least one observation has yielded, so `recompute` can resolve
    /// the empty-vs-still-loading phase honestly.
    @ObservationIgnored
    private var hasReceivedConfirmed = false

    @ObservationIgnored
    private var fetchTask: Task<Void, Never>?
    @ObservationIgnored
    private var messagesObservationTask: Task<Void, Never>?
    @ObservationIgnored
    private var outboundObservationTask: Task<Void, Never>?

    /// A confirmed outgoing message is treated as the delivered twin of an
    /// optimistic send when their bodies match and they were authored within this
    /// window of the outbound row's creation time. Generous enough to absorb send
    /// latency + clock skew, tight enough that a genuinely distinct repeat of the
    /// same text minutes later still shows as its own bubble.
    @ObservationIgnored
    private let dedupWindow: TimeInterval = 120

    // MARK: Functions

    init(
        accountScope: AccountScope,
        appDatabase: AppDatabase,
        correspondentId: Components.Schemas.PersonID,
        correspondentName: String,
        myPersonId: Components.Schemas.PersonID?,
        alertService: AlertServiceType,
        unreadCountService: UnreadCountServiceType
    ) {
        self.accountScope = accountScope
        self.appDatabase = appDatabase
        self.correspondentId = correspondentId
        self.correspondentName = correspondentName
        myServerPersonId = myPersonId.map { Int64($0) }
        accountId = appDatabase.accountRowIdSync(forKeychainId: accountScope.accountKeychainId)
        self.alertService = alertService
        self.unreadCountService = unreadCountService
    }

    deinit {
        fetchTask?.cancel()
        messagesObservationTask?.cancel()
        outboundObservationTask?.cancel()
    }

    /// Start the GRDB observations and kick off a one-shot server refresh.
    ///
    /// The UI is driven by the observations (not the fetch result directly): the
    /// fetch imports a fresh server page into the persistent store, and the
    /// `observeMessages` stream re-emits with the updated rows. A failed fetch is
    /// non-fatal — the already-persisted messages still render; only when there
    /// is nothing persisted to show AND the fetch failed do we surface `.error`.
    func start() {
        guard accountId != nil else {
            // No account row resolved: nothing to observe. Stay empty rather than
            // claiming an error — a signed-out / not-yet-imported account has no
            // thread, and the empty state reads correctly.
            phase = .loaded
            return
        }
        startMessagesObservation()
        startOutboundObservation()
        refresh()
    }

    private func startMessagesObservation() {
        guard let accountId else { return }
        let correspondentServerPersonId = Int64(correspondentId)
        messagesObservationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let stream = appDatabase.observeMessages(
                accountId: accountId,
                correspondentServerPersonId: correspondentServerPersonId
            )
            for await rows in stream {
                if Task.isCancelled { break }
                confirmedMessages = rows
                hasReceivedConfirmed = true
                recompute()
            }
        }
    }

    private func startOutboundObservation() {
        let recipientServerPersonId = Int64(correspondentId)
        let accountKeychainId = accountScope.accountKeychainId
        outboundObservationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let stream = appDatabase.observeOutboundDMs(
                recipientServerPersonId: recipientServerPersonId,
                accountKeychainId: accountKeychainId
            )
            for await rows in stream {
                if Task.isCancelled { break }
                outboundRows = rows
                recompute()
            }
        }
    }

    /// Re-fetch the thread from the server and import it into the persistent
    /// store, then mark the correspondent's unread messages read. Safe to call
    /// repeatedly (pull-to-refresh / re-open). Never blocks the optimistic UI.
    func refresh(markRead: Bool = true) {
        guard let accountId else { return }
        fetchTask?.cancel()
        fetchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let service = accountScope.lemmyService
            do {
                let response = try await service.fetchPrivateMessages(unreadOnly: false, page: 1)
                if Task.isCancelled { return }
                // Import the whole page; the read layer filters to this thread.
                // upsert-only (a server page is partial), so nothing is deleted.
                try await appDatabase.upsertPrivateMessages(
                    views: response.private_messages,
                    accountId: accountId
                )
                if markRead { await markCorrespondentMessagesRead() }
            } catch {
                if Task.isCancelled { return }
                logger.error("DM thread refresh failed: \(String(describing: error), privacy: .public)")
                // Degrade gracefully: only error out when there is genuinely
                // nothing persisted to show. Otherwise the stale-but-present
                // thread keeps rendering offline.
                if confirmedMessages.isEmpty, outboundRows.isEmpty {
                    phase = .error
                }
            }
        }
    }

    /// Marks unread incoming messages read when the thread opens (also invoked by
    /// `refresh`). Idempotent.
    func markReadOnOpen() {
        Task { @MainActor [weak self] in
            await self?.markCorrespondentMessagesRead()
        }
    }

    /// Marks every unread message from the correspondent as read: the server mark
    /// (Lemmy has no local read state to refresh) PLUS a local write so the
    /// observation reflects it immediately, then decrements the badge.
    private func markCorrespondentMessagesRead() async {
        guard let accountId else { return }
        let service = accountScope.lemmyService
        let correspondentServerPersonId = Int64(correspondentId)
        let unread = confirmedMessages.filter {
            !$0.isRead && $0.creatorServerPersonId == correspondentServerPersonId
        }
        guard !unread.isEmpty else { return }

        var marked = 0
        for message in unread {
            do {
                try await service.markPrivateMessageAsRead(
                    privateMessageId: Components.Schemas.PrivateMessageID(message.serverMessageId),
                    read: true
                )
                // Reflect the read state in the persisted store so the
                // observation re-emits with the unread dot cleared.
                try await appDatabase.setPrivateMessageRead(
                    accountId: accountId,
                    serverMessageId: message.serverMessageId,
                    isRead: true
                )
                marked += 1
            } catch {
                logger.error("Mark DM read failed: \(String(describing: error), privacy: .public)")
            }
        }
        if marked > 0 {
            unreadCountService.decrement(replies: 0, mentions: 0, privateMessages: marked)
        }
    }

    /// Send a new message. Fire-and-forget: `sendDirectMessage` returns
    /// immediately after a fast DB write (the optimistic bubble arrives via the
    /// outbound observation), so this never blocks and several sends can be in
    /// flight at once. We do NOT await the network — see the type doc.
    ///
    /// Guards `.privateMessages` before doing anything else. This is a
    /// backstop for a thread opened (or left open) before the capability
    /// flipped underneath it — the view controller already disables the input
    /// bar for a thread that opens gated, but that check runs once at open
    /// time, not on every keystroke. Checking again here mirrors
    /// `LemmyService.sendDirectMessage`'s own `requireCapability` gate (which
    /// would reject the same send one layer down), but catches it before
    /// spawning the Task at all, so a stale-but-still-enabled input bar never
    /// round-trips into the composer outbox for content we already know will
    /// be rejected. Surfaces through the same `alertService.handle` path an
    /// ordinary send failure uses — no new failure mechanism.
    func send(_ rawText: String) {
        let content = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        guard accountScope.capabilities.can(.privateMessages) else {
            logger.error("Send DM blocked: private messages unsupported by this instance")
            alertService.handle(LemmyServiceError.unsupportedByInstance(.privateMessages), for: .sendPrivateMessage)
            return
        }
        let recipientServerPersonId = Int64(correspondentId)
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await accountScope.lemmyService.sendDirectMessage(
                    body: content,
                    recipientServerPersonId: recipientServerPersonId
                )
            } catch {
                logger.error("Send DM failed to enqueue: \(String(describing: error), privacy: .public)")
                alertService.handle(error, for: .sendPrivateMessage)
            }
        }
    }

    /// Retry a failed optimistic send (re-enqueues the same outbound row).
    func retry(clientToken: String) {
        Task { await accountScope.lemmyService.retryComposition(clientToken: clientToken) }
    }

    /// Permanently discard a failed optimistic send (drops the outbound row).
    func discard(clientToken: String) {
        Task { await accountScope.lemmyService.discardComposition(clientToken: clientToken) }
    }

    // MARK: Draft autosave

    /// Persist the in-progress (unsent) input text as the per-recipient DM draft,
    /// or clear it when empty. Singleton per correspondent (keyed by
    /// `dmDraftKey`), so a re-open restores exactly what the user last typed.
    /// Fire-and-forget; failures are non-fatal (the draft is a convenience).
    func autosaveDraft(_ text: String) {
        let recipientServerPersonId = Int64(correspondentId)
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await accountScope.lemmyService.saveDirectMessageDraft(
                    body: text,
                    recipientServerPersonId: recipientServerPersonId
                )
            } catch {
                logger.error("DM draft autosave failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Load the saved per-recipient DM draft text, if any. Returns nil when there
    /// is no draft, the body is empty, or the account row can't be resolved.
    func loadDraft() async -> String? {
        let draftKey = OutboundContentRecord.dmDraftKey(
            recipientServerPersonId: Int64(correspondentId)
        )
        do {
            guard let record = try await accountScope.lemmyService.loadDraft(draftKey: draftKey) else {
                return nil
            }
            let body = record.body.trimmingCharacters(in: .whitespacesAndNewlines)
            return body.isEmpty ? nil : record.body
        } catch {
            logger.error("DM draft load failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    // MARK: Merge

    /// The synthetic bubble id for an optimistic outbound row. A large negative
    /// base keeps it well clear of any real (positive) server message id, so the
    /// confirmed and optimistic id spaces never collide — mirroring the
    /// post-detail pending-comment merge.
    private static func optimisticBubbleId(for record: OutboundContentRecord) -> Int64 {
        -(1_000_000 + (record.id ?? 0))
    }

    /// Rebuild `bubbles` from the two observation snapshots.
    ///
    /// Confirmed messages render in their published order. Each still
    /// pending/failed outbound row is appended as an optimistic OUTGOING bubble.
    ///
    /// Dedup window: the performer imports the confirmed `PrivateMessageView`
    /// (which makes it show via `observeMessages`) and THEN the generic outbox
    /// path deletes the outbound row — so for a brief window BOTH a confirmed
    /// outgoing message and its still-present outbound row exist. To avoid a
    /// duplicate-bubble flash on success, an outbound row is DROPPED when a
    /// confirmed outgoing message already matches it: same body, authored by me,
    /// published within `dedupWindow` of the outbound row's `createdAt`. Each
    /// confirmed twin is consumed at most once, so two identical rapid sends still
    /// each keep their own optimistic bubble until both confirm.
    private func recompute() {
        var confirmedBubbles: [DMBubbleItem] = confirmedMessages
            .filter { !$0.isDeleted }
            .map { row in
                DMBubbleItem(
                    id: row.serverMessageId,
                    content: row.content,
                    published: row.published,
                    isOutgoing: isOutgoing(row),
                    pendingStatus: nil,
                    clientToken: nil
                )
            }

        // Build the dedup pool: confirmed OUTGOING messages keyed by body, each
        // carrying its publish time. An outbound row consumes (and removes) one
        // matching twin so concurrent identical sends don't all collapse onto a
        // single confirmed message.
        //
        // Known cosmetic edge: two genuinely-distinct identical sends that confirm
        // within the same window can have their optimistic bubbles matched to the
        // "wrong" confirmed twin (the pool keys on body, not identity). This only
        // affects which bubble is dropped during the brief coexist window and
        // self-heals once both confirm — accepted as not worth identity tracking.
        var confirmedOutgoingByBody: [String: [Date]] = [:]
        for bubble in confirmedBubbles where bubble.isOutgoing {
            confirmedOutgoingByBody[bubble.content, default: []].append(bubble.published)
        }

        var optimisticBubbles: [DMBubbleItem] = []
        for record in outboundRows {
            let createdAt = Date(timeIntervalSince1970: record.createdAt)
            // Drop this optimistic bubble if a confirmed outgoing twin exists.
            if let candidates = confirmedOutgoingByBody[record.body],
               let matchIndex = candidates.firstIndex(where: {
                   abs($0.timeIntervalSince(createdAt)) <= dedupWindow
               })
            {
                confirmedOutgoingByBody[record.body]?.remove(at: matchIndex)
                continue
            }

            let status: DMBubbleItem.PendingStatus =
                record.status == OutboundStatus.failed.rawValue ? .failed : .sending
            optimisticBubbles.append(DMBubbleItem(
                id: Self.optimisticBubbleId(for: record),
                content: record.body,
                published: createdAt,
                isOutgoing: true,
                pendingStatus: status,
                clientToken: record.clientToken
            ))
        }

        confirmedBubbles.append(contentsOf: optimisticBubbles)
        // Stable chat order (oldest first), tie-broken on id so a confirmed and an
        // optimistic bubble sharing a timestamp keep a deterministic position.
        bubbles = confirmedBubbles.sorted {
            $0.published == $1.published ? $0.id < $1.id : $0.published < $1.published
        }

        // Phase resolves to `.loaded` only once the CONFIRMED-messages observation
        // has emitted at least once. The outbound observation can fire first (an
        // optimistic bubble exists before the persisted messages stream yields); if
        // we flipped to `.loaded` then, the thread would flash with only the
        // optimistic bubble(s) before the real history appears. Gating on
        // `hasReceivedConfirmed` keeps `.loading` until the source of truth has been
        // read. Once confirmed, we still don't clobber an in-flight `.error` unless
        // there is now something to show.
        if hasReceivedConfirmed, phase != .error || !bubbles.isEmpty {
            phase = .loaded
        }
    }

    /// True if `message` was authored by the account holder (right-aligned). When
    /// `myServerPersonId` is unknown, anything not from the correspondent is
    /// treated as outgoing — matching the creator fallback in
    /// `observeConversations`.
    private func isOutgoing(_ message: PrivateMessageRow) -> Bool {
        if let myServerPersonId {
            return message.creatorServerPersonId == myServerPersonId
        }
        return message.creatorServerPersonId != Int64(correspondentId)
    }
}
