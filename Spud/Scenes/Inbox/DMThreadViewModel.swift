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

/// Drives a single DM thread (chat-style). Holds the messages with the
/// correspondent, sends new messages via `LemmyService.sendPrivateMessage`, and
/// marks the correspondent's unread messages read on open. Content is transient
/// (fetched per-thread, like the rest of the inbox).
@MainActor
@Observable
final class DMThreadViewModel {
    // MARK: Observable state

    private(set) var messages: [InboxMessageItem]
    private(set) var phase: InboxPhase = .loaded
    var isSending: Bool = false

    // MARK: Private

    let accountKeychainId: String
    let correspondentId: Components.Schemas.PersonID
    let correspondentName: String

    @ObservationIgnored
    private let myPersonId: Components.Schemas.PersonID?
    @ObservationIgnored
    private let accountService: AccountServiceType
    @ObservationIgnored
    private let alertService: AlertServiceType
    @ObservationIgnored
    private let unreadCountService: UnreadCountServiceType

    @ObservationIgnored
    private var loadTask: Task<Void, Never>?

    // MARK: Functions

    init(
        accountKeychainId: String,
        correspondentId: Components.Schemas.PersonID,
        correspondentName: String,
        myPersonId: Components.Schemas.PersonID?,
        initialMessages: [InboxMessageItem],
        accountService: AccountServiceType,
        alertService: AlertServiceType,
        unreadCountService: UnreadCountServiceType
    ) {
        self.accountKeychainId = accountKeychainId
        self.correspondentId = correspondentId
        self.correspondentName = correspondentName
        self.myPersonId = myPersonId
        messages = initialMessages
        self.accountService = accountService
        self.alertService = alertService
        self.unreadCountService = unreadCountService
    }

    deinit {
        loadTask?.cancel()
    }

    /// Returns true if `message` was sent by the account holder (right-aligned
    /// in the chat). When `myPersonId` is unknown, anything not from the
    /// correspondent is treated as outgoing.
    func isOutgoing(_ message: InboxMessageItem) -> Bool {
        if let myPersonId {
            return message.creatorId == myPersonId
        }
        return message.creatorId != correspondentId
    }

    /// Reloads the full thread from the server (used after sending) and marks
    /// the correspondent's unread messages as read.
    func reload(markRead: Bool) {
        loadTask?.cancel()
        let myPersonId = myPersonId
        let correspondentId = correspondentId
        loadTask = Task { [weak self] in
            guard let self else { return }
            let service = accountService.lemmyService(forAccountKeychainId: accountKeychainId)
            do {
                let response = try await service.fetchPrivateMessages(unreadOnly: false, page: 1)
                if Task.isCancelled { return }
                let thread = InboxConversationBuilder.conversations(
                    from: response.private_messages,
                    myPersonId: myPersonId
                ).first { $0.correspondentId == correspondentId }
                if let thread {
                    messages = thread.messages
                }
                phase = .loaded

                if markRead {
                    await markCorrespondentMessagesRead()
                }
            } catch {
                if Task.isCancelled { return }
                logger.error("DM thread reload failed: \(String(describing: error), privacy: .public)")
                phase = .error
            }
        }
    }

    /// Marks every unread message from the correspondent as read, decrementing
    /// the badge accordingly.
    private func markCorrespondentMessagesRead() async {
        let service = accountService.lemmyService(forAccountKeychainId: accountKeychainId)
        let unread = messages.filter { !$0.isRead && $0.creatorId == correspondentId }
        guard !unread.isEmpty else { return }

        var marked = 0
        for message in unread {
            do {
                try await service.markPrivateMessageAsRead(
                    privateMessageId: message.privateMessageId,
                    read: true
                )
                marked += 1
            } catch {
                logger.error("Mark DM read failed: \(String(describing: error), privacy: .public)")
            }
        }
        if marked > 0 {
            messages = messages.map { msg in
                guard !msg.isRead, msg.creatorId == correspondentId else { return msg }
                var copy = msg
                copy.isRead = true
                return copy
            }
            unreadCountService.decrement(replies: 0, mentions: 0, privateMessages: marked)
        }
    }

    /// Marks unread incoming messages read when the thread opens.
    func markReadOnOpen() {
        Task { [weak self] in
            await self?.markCorrespondentMessagesRead()
        }
    }

    func send(_ rawText: String) {
        let content = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, !isSending else { return }
        isSending = true
        let correspondentId = correspondentId
        Task { [weak self] in
            guard let self else { return }
            let service = accountService.lemmyService(forAccountKeychainId: accountKeychainId)
            do {
                let view = try await service.sendPrivateMessage(content: content, recipientId: correspondentId)
                if Task.isCancelled { return }
                // Append the sent message optimistically (server response carries
                // the canonical row), then keep ordering by published date.
                let sent = InboxMessageItem(view: view)
                if !messages.contains(where: { $0.privateMessageId == sent.privateMessageId }) {
                    messages = (messages + [sent]).sorted { $0.published < $1.published }
                }
                isSending = false
            } catch {
                if Task.isCancelled { return }
                logger.error("Send DM failed: \(String(describing: error), privacy: .public)")
                alertService.handle(error, for: .sendPrivateMessage)
                isSending = false
            }
        }
    }
}
