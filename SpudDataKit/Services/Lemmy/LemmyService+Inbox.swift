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
    ) async throws -> Components.Schemas.GetRepliesResponse {
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
    ) async throws -> Components.Schemas.GetPersonMentionsResponse {
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
    ) async throws -> Components.Schemas.PrivateMessagesResponse {
        try await requireCapability(.privateMessages)

        guard !accountIsSignedOut else {
            throw LemmyServiceError.requiresAuthentication
        }

        logger.debug("""
            Fetch private messages. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            unreadOnly=\(unreadOnly, privacy: .public) page=\(page, privacy: .public)
            """)

        do {
            return try await api.getPrivateMessages(
                unreadOnly: unreadOnly,
                page: page
            )
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

        let response: Components.Schemas.GetUnreadCountResponse
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
        commentReplyId: Components.Schemas.CommentReplyID,
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
        personMentionId: Components.Schemas.PersonMentionID,
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
        privateMessageId: Components.Schemas.PrivateMessageID,
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
        recipientId: Components.Schemas.PersonID
    ) async throws -> Components.Schemas.PrivateMessageView {
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

        let response: Components.Schemas.PrivateMessageResponse
        do {
            response = try await api.createPrivateMessage(content: content, recipientID: recipientId)
        } catch {
            logger.error("""
                Send private message failed. recipientId=\(recipientId, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        return response.private_message_view
    }
}
