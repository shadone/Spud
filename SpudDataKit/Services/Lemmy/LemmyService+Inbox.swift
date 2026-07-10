//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import OSLog

private let logger = Logger.lemmyService

// MARK: - Inbox

/// Inbox: replies, mentions, and private messages — fetch, unread count, and mark-as-read.
public extension LemmyService {
    func fetchReplies(
        unreadOnly: Bool,
        page: Int64
    ) async throws -> Lemmy.GetRepliesResponse {
        try await requireCapability(.inbox)

        guard !accountIsSignedOut else {
            throw LemmyServiceError.requiresAuthentication
        }

        logger.debug("""
            Fetch inbox replies. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            unreadOnly=\(unreadOnly, privacy: .public) page=\(page, privacy: .public)
            """)

        do {
            return try await api.getReplies(
                commentSort: .New,
                unreadOnly: unreadOnly,
                page: page
            )
        } catch {
            logger.error("""
                Fetch inbox replies failed. \
                account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }
    }

    func fetchMentions(
        unreadOnly: Bool,
        page: Int64
    ) async throws -> Lemmy.GetPersonMentionsResponse {
        try await requireCapability(.inbox)

        guard !accountIsSignedOut else {
            throw LemmyServiceError.requiresAuthentication
        }

        logger.debug("""
            Fetch inbox mentions. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            unreadOnly=\(unreadOnly, privacy: .public) page=\(page, privacy: .public)
            """)

        do {
            return try await api.getPersonMentions(
                commentSort: .New,
                unreadOnly: unreadOnly,
                page: page
            )
        } catch {
            logger.error("""
                Fetch inbox mentions failed. \
                account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }
    }

    func fetchPrivateMessages(
        unreadOnly: Bool,
        page: Int64
    ) async throws -> [IncomingPrivateMessage] {
        try await requireCapability(.privateMessages)

        guard !accountIsSignedOut else {
            throw LemmyServiceError.requiresAuthentication
        }

        logger.debug("""
            Fetch private messages. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            unreadOnly=\(unreadOnly, privacy: .public) page=\(page, privacy: .public)
            """)

        // The neutral surface has no standalone private-message list; DMs arrive
        // through the unified notification feed. Fetch it and keep only the
        // private-message entries, pairing each with the notification's read state.
        // NOTE: `page` maps to an opaque cursor ("N" on a v3 backend); on v3 the
        // notification list is a single fan-out page, so paging degrades. See the
        // Phase 6 report follow-ups (full inbox → listNotificationsNeutral).
        do {
            let cursor = page <= 1 ? nil : Cursor(rawValue: String(page))
            let notifications = try await api.listNotificationsNeutral(
                unreadOnly: unreadOnly,
                pageCursor: cursor
            )
            return notifications.items.compactMap { notification in
                guard case let .privateMessage(view) = notification.data else { return nil }
                return IncomingPrivateMessage(view: view, isRead: notification.notification.isRead)
            }
        } catch {
            logger.error("""
                Fetch private messages failed. \
                account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }
    }

    func unreadCount() async throws -> UnreadCount {
        guard !accountIsSignedOut else {
            throw LemmyServiceError.requiresAuthentication
        }

        guard await instanceCapabilities().can(.inbox) else {
            // Scheduler-polled: the badge simply reads zero until Spud speaks
            // this instance's API - throwing here would spam retries/logs.
            return .zero
        }

        let response: Lemmy.GetUnreadCountResponse
        do {
            response = try await api.getUnreadCount()
        } catch {
            logger.error("""
                Fetch unread count failed. \
                account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        return UnreadCount(
            replies: Int(response.replies),
            mentions: Int(response.mentions),
            privateMessages: Int(response.private_messages)
        )
    }

    func markReplyAsRead(
        commentReplyId: Lemmy.CommentReplyID,
        read: Bool
    ) async throws {
        try await requireCapability(.inbox)

        guard !accountIsSignedOut else {
            throw LemmyServiceError.requiresAuthentication
        }

        logger.debug("""
            Mark reply as read. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            commentReplyId=\(commentReplyId, privacy: .public) read=\(read, privacy: .public)
            """)

        do {
            try await api.markCommentReplyAsRead(commentReplyID: commentReplyId, read: read)
        } catch {
            logger.error("""
                Mark reply as read failed. commentReplyId=\(commentReplyId, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }
    }

    func markMentionAsRead(
        personMentionId: Lemmy.PersonMentionID,
        read: Bool
    ) async throws {
        try await requireCapability(.inbox)

        guard !accountIsSignedOut else {
            throw LemmyServiceError.requiresAuthentication
        }

        logger.debug("""
            Mark mention as read. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            personMentionId=\(personMentionId, privacy: .public) read=\(read, privacy: .public)
            """)

        do {
            try await api.markPersonMentionAsRead(personMentionID: personMentionId, read: read)
        } catch {
            logger.error("""
                Mark mention as read failed. personMentionId=\(personMentionId, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }
    }

    func markPrivateMessageAsRead(
        privateMessageId: Lemmy.PrivateMessageID,
        read: Bool
    ) async throws {
        try await requireCapability(.inbox)

        guard !accountIsSignedOut else {
            throw LemmyServiceError.requiresAuthentication
        }

        logger.debug("""
            Mark private message as read. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            privateMessageId=\(privateMessageId, privacy: .public) read=\(read, privacy: .public)
            """)

        do {
            try await api.markPrivateMessageAsRead(privateMessageID: privateMessageId, read: read)
        } catch {
            logger.error("""
                Mark private message as read failed. privateMessageId=\(privateMessageId, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }
    }

    func markAllInboxAsRead() async throws {
        try await requireCapability(.inbox)

        guard !accountIsSignedOut else {
            throw LemmyServiceError.requiresAuthentication
        }

        logger.debug("""
            Mark all inbox as read. \
            account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash))
            """)

        // Lemmy's markAllAsRead only covers replies + mentions; private
        // messages must be marked individually. Fetch the unread messages and
        // mark each, then call markAllAsRead for the comment-based items.
        do {
            let unreadMessages = try await api.getPrivateMessages(unreadOnly: true, page: 1)
            for view in unreadMessages.private_messages where !view.private_message.read {
                _ = try? await api.markPrivateMessageAsRead(
                    privateMessageID: view.private_message.id,
                    read: true
                )
            }
        } catch {
            logger.error("""
                Mark all inbox (private messages) failed. \
                \(String(describing: error), privacy: .public)
                """)
            // Non-fatal: still attempt to clear replies/mentions below.
        }

        do {
            _ = try await api.markAllAsRead()
        } catch {
            logger.error("""
                Mark all inbox (replies/mentions) failed. \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }
    }

    @discardableResult
    func sendPrivateMessage(
        content: String,
        recipientId: Lemmy.PersonID
    ) async throws -> Lemmy.PrivateMessageView {
        try await requireCapability(.privateMessages)

        guard !accountIsSignedOut else {
            logger.debug("""
                Send private message rejected - account is signed out. \
                account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
                recipientId=\(recipientId, privacy: .public)
                """)
            throw LemmyServiceError.requiresAuthentication
        }

        logger.debug("""
            Send private message. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            recipientId=\(recipientId, privacy: .public)
            """)

        let view: Lemmy.PrivateMessageView
        do {
            view = try await api.createPrivateMessageNeutral(
                content: content,
                recipientId: Int64(recipientId)
            )
        } catch {
            logger.error("""
                Send private message failed. recipientId=\(recipientId, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        return view
    }
}
