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

    // MARK: Private

    @ObservationIgnored
    let isSignedIn: Bool

    @ObservationIgnored
    private let accountScope: AccountScope
    @ObservationIgnored
    private let alertService: AlertServiceType
    @ObservationIgnored
    private let unreadCountService: UnreadCountServiceType
    @ObservationIgnored
    private let myPersonId: Components.Schemas.PersonID?

    @ObservationIgnored
    private var repliesTask: Task<Void, Never>?
    @ObservationIgnored
    private var mentionsTask: Task<Void, Never>?
    @ObservationIgnored
    private var messagesTask: Task<Void, Never>?

    // MARK: Functions

    init(
        accountScope: AccountScope,
        isSignedIn: Bool,
        myPersonId: Components.Schemas.PersonID?,
        alertService: AlertServiceType,
        unreadCountService: UnreadCountServiceType
    ) {
        self.accountScope = accountScope
        self.isSignedIn = isSignedIn
        self.myPersonId = myPersonId
        self.alertService = alertService
        self.unreadCountService = unreadCountService
    }

    deinit {
        repliesTask?.cancel()
        mentionsTask?.cancel()
        messagesTask?.cancel()
    }

    func scopeChanged(_ newScope: InboxScope) {
        guard newScope != scope else { return }
        scope = newScope
    }

    /// Loads (or reloads) every scope. Called on appear and on pull-to-refresh.
    func loadAll() {
        guard isSignedIn else { return }
        loadReplies()
        loadMentions()
        loadMessages()
        Task { await unreadCountService.refresh(accountKeychainId: accountScope.accountKeychainId) }
    }

    func loadReplies() {
        guard isSignedIn else { return }
        repliesTask?.cancel()
        repliesPhase = .loading
        repliesTask = Task { [weak self] in
            guard let self else { return }
            let service = accountScope.lemmyService
            do {
                let response = try await service.fetchReplies(unreadOnly: false, page: 1)
                if Task.isCancelled { return }
                replies = response.replies.map(InboxReplyItem.init)
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
                let response = try await service.fetchMentions(unreadOnly: false, page: 1)
                if Task.isCancelled { return }
                mentions = response.mentions.map(InboxMentionItem.init)
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

    func loadMessages() {
        guard isSignedIn else { return }
        messagesTask?.cancel()
        messagesPhase = .loading
        let myPersonId = myPersonId
        messagesTask = Task { [weak self] in
            guard let self else { return }
            let service = accountScope.lemmyService
            do {
                let response = try await service.fetchPrivateMessages(unreadOnly: false, page: 1)
                if Task.isCancelled { return }
                conversations = InboxConversationBuilder.conversations(
                    from: response.private_messages,
                    myPersonId: myPersonId
                )
                messagesPhase = .loaded
            } catch {
                if Task.isCancelled { return }
                logger.error("Fetch private messages failed: \(String(describing: error), privacy: .public)")
                alertService.handle(error, for: .fetchInbox)
                conversations = []
                messagesPhase = .error
            }
        }
    }

    // MARK: Mark read

    /// Mark a reply read (optimistically updates the row and the badge), then
    /// confirms with the server.
    func markReplyRead(_ item: InboxReplyItem) {
        guard isSignedIn, !item.isRead else { return }
        // Optimistic local update.
        replies = replies.map { $0.commentReplyId == item.commentReplyId ? $0.markedRead() : $0 }
        unreadCountService.decrement(replies: 1, mentions: 0, privateMessages: 0)

        Task { [weak self] in
            guard let self else { return }
            let service = accountScope.lemmyService
            do {
                try await service.markReplyAsRead(commentReplyId: item.commentReplyId, read: true)
            } catch {
                logger.error("Mark reply read failed: \(String(describing: error), privacy: .public)")
                alertService.handle(error, for: .markInboxItemRead)
            }
        }
    }

    func markMentionRead(_ item: InboxMentionItem) {
        guard isSignedIn, !item.isRead else { return }
        mentions = mentions.map { $0.personMentionId == item.personMentionId ? $0.markedRead() : $0 }
        unreadCountService.decrement(replies: 0, mentions: 1, privateMessages: 0)

        Task { [weak self] in
            guard let self else { return }
            let service = accountScope.lemmyService
            do {
                try await service.markMentionAsRead(personMentionId: item.personMentionId, read: true)
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
