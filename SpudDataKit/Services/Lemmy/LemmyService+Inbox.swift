//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import OSLog

private let logger = Logger.lemmyService

// MARK: - Inbox value types

/// A backend-neutral handle for marking one comment-based inbox item (a reply or
/// a mention) as read.
///
/// The two Lemmy APIs identify an inbox item by different ids, so this carries
/// whichever the producing backend supplied and routes the mark-read call to the
/// matching endpoint (see ``LemmyService/markInboxItemAsRead(reference:read:)``):
/// - v3 has no unified notification id — a reply is marked read by its
///   `CommentReplyID` and a mention by its `PersonMentionID`, via two separate
///   endpoints.
/// - v4 has a single unified inbox — every item is marked read by its
///   `Notification` id.
public enum InboxItemReadReference: Sendable, Hashable {
    /// A v3 reply, marked read via `markCommentReplyAsRead`.
    case commentReply(Lemmy.CommentReplyID)
    /// A v3 mention, marked read via `markPersonMentionAsRead`.
    case personMention(Lemmy.PersonMentionID)
    /// A v4 unified-inbox notification, marked read via
    /// `markNotificationAsReadNeutral`.
    case notification(Int64)
}

/// A single comment-based inbox notification — a reply to, or a mention of, the
/// account holder — decoupled from the wire shape.
///
/// Both Lemmy APIs surface replies and mentions, but in different shapes: v3's
/// `CommentReplyView` / `PersonMentionView` (each carrying its own per-item read
/// id) versus v4's unified `NotificationView` (carrying a notification id and a
/// `CommentView` payload). This is the version-neutral projection Spud's Inbox
/// renders — the display fields plus a backend-appropriate
/// ``InboxItemReadReference`` so the item can be marked read on whichever API
/// produced it. Transient (returned to the caller, like `search`), never mirrored
/// into the persistent store.
public struct InboxCommentNotification: Sendable, Equatable {
    /// How to mark this item read on its originating backend.
    public let readReference: InboxItemReadReference
    /// The replying/mentioning comment's server id.
    public let serverCommentId: Lemmy.CommentID
    /// The post the comment belongs to — used to open PostDetail on tap.
    public let serverPostId: Lemmy.PostID
    /// The comment author's server person id.
    public let serverPersonId: Lemmy.PersonID
    public let creatorName: String
    public let content: String
    public let postTitle: String
    public let communityName: String
    public let score: Int64
    public let published: Date
    public let isRead: Bool

    public init(
        readReference: InboxItemReadReference,
        serverCommentId: Lemmy.CommentID,
        serverPostId: Lemmy.PostID,
        serverPersonId: Lemmy.PersonID,
        creatorName: String,
        content: String,
        postTitle: String,
        communityName: String,
        score: Int64,
        published: Date,
        isRead: Bool
    ) {
        self.readReference = readReference
        self.serverCommentId = serverCommentId
        self.serverPostId = serverPostId
        self.serverPersonId = serverPersonId
        self.creatorName = creatorName
        self.content = content
        self.postTitle = postTitle
        self.communityName = communityName
        self.score = score
        self.published = published
        self.isRead = isRead
    }
}

// MARK: - Inbox

/// Inbox: replies, mentions, and private messages — fetch, unread count, and mark-as-read.
///
/// Each fetch/mark dispatches on ``LemmyKit/ApiVersion``: a v3 instance uses the
/// per-kind v3 endpoints (which carry the per-item read ids Spud's mark-read
/// path needs), while a v4 instance uses the native unified notification inbox
/// (`listNotificationsNeutral` / `markNotificationAsReadNeutral` /
/// `unreadCountsNeutral`). Going through the neutral inbox on v3 would fan out
/// and drop the per-item ids, so v3 deliberately keeps the concrete v3 shapes.
public extension LemmyService {
    func fetchReplies(
        unreadOnly: Bool,
        page: Int64
    ) async throws -> [InboxCommentNotification] {
        try await requireCapability(.inbox)

        guard !accountIsSignedOut else {
            throw LemmyServiceError.requiresAuthentication
        }

        logger.debug("""
            Fetch inbox replies. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            unreadOnly=\(unreadOnly, privacy: .public) page=\(page, privacy: .public)
            """)

        do {
            switch await api.apiVersion {
            case .v3:
                let response = try await api.getReplies(
                    commentSort: .New,
                    unreadOnly: unreadOnly,
                    page: page
                )
                return response.replies.map(InboxCommentNotification.init(reply:))

            case .v4:
                let notifications = try await api.listNotificationsNeutral(
                    unreadOnly: unreadOnly,
                    pageCursor: Self.inboxCursor(forPage: page),
                    kind: .reply
                )
                return notifications.items.compactMap(InboxCommentNotification.init(notification:))
            }
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
    ) async throws -> [InboxCommentNotification] {
        try await requireCapability(.inbox)

        guard !accountIsSignedOut else {
            throw LemmyServiceError.requiresAuthentication
        }

        logger.debug("""
            Fetch inbox mentions. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            unreadOnly=\(unreadOnly, privacy: .public) page=\(page, privacy: .public)
            """)

        do {
            switch await api.apiVersion {
            case .v3:
                let response = try await api.getPersonMentions(
                    commentSort: .New,
                    unreadOnly: unreadOnly,
                    page: page
                )
                return response.mentions.map(InboxCommentNotification.init(mention:))

            case .v4:
                let notifications = try await api.listNotificationsNeutral(
                    unreadOnly: unreadOnly,
                    pageCursor: Self.inboxCursor(forPage: page),
                    kind: .mention
                )
                return notifications.items.compactMap(InboxCommentNotification.init(notification:))
            }
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
        pageCursor: String?
    ) async throws -> (messages: [IncomingPrivateMessage], nextCursor: String?) {
        try await requireCapability(.privateMessages)

        guard !accountIsSignedOut else {
            throw LemmyServiceError.requiresAuthentication
        }

        logger.debug("""
            Fetch private messages. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            unreadOnly=\(unreadOnly, privacy: .public) pageCursor=\(pageCursor ?? "nil", privacy: .public)
            """)

        // The neutral private-message list is cursor-paginated: on v4 it pages the
        // native unified inbox filtered to private messages; on v3 it pages the flat
        // all-conversations list with a synthesized cursor. Spud persists the cursor
        // as a bare string, so bridge in both directions (as `fetchFeed` does). Each
        // `PrivateMessageListItem` pairs the neutral view with its read state.
        let cursor = pageCursor.map { Cursor(rawValue: $0) }
        do {
            let page = try await api.getPrivateMessagesNeutral(
                unreadOnly: unreadOnly,
                pageCursor: cursor
            )
            let messages = page.items.map { item in
                IncomingPrivateMessage(view: item.view, isRead: item.isRead)
            }
            return (messages: messages, nextCursor: page.nextPage?.rawValue)
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
            // this instance's API - throwing here would spam retries/logs. Inert
            // now that no Lemmy version gates the inbox (see InstanceCapabilities).
            return .zero
        }

        let counts: UnreadCounts
        do {
            counts = try await api.unreadCountsNeutral()
        } catch {
            logger.error("""
                Fetch unread count failed. \
                account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        // v3 reports a per-kind breakdown; v4 reports only a combined total (no
        // breakdown), so fall back to the total-only shape when the per-kind
        // fields are absent. The badge reads `UnreadCount.total` either way.
        if let replies = counts.replies, let mentions = counts.mentions, let privateMessages = counts.privateMessages {
            return UnreadCount(
                replies: Int(replies),
                mentions: Int(mentions),
                privateMessages: Int(privateMessages)
            )
        }
        return UnreadCount(total: Int(counts.total))
    }

    /// Mark a single comment-based inbox item (reply or mention) read/unread,
    /// routing to the endpoint that matches the reference's originating backend
    /// (see ``InboxItemReadReference``).
    func markInboxItemAsRead(
        reference: InboxItemReadReference,
        read: Bool
    ) async throws {
        try await requireCapability(.inbox)

        guard !accountIsSignedOut else {
            throw LemmyServiceError.requiresAuthentication
        }

        logger.debug("""
            Mark inbox item as read. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            reference=\(String(describing: reference), privacy: .public) read=\(read, privacy: .public)
            """)

        do {
            switch reference {
            case let .commentReply(id):
                try await api.markCommentReplyAsRead(commentReplyID: id, read: read)
            case let .personMention(id):
                try await api.markPersonMentionAsRead(personMentionID: id, read: read)
            case let .notification(id):
                try await api.markNotificationAsReadNeutral(id: id, read: read)
            }
        } catch {
            logger.error("""
                Mark inbox item as read failed. \
                reference=\(String(describing: reference), privacy: .public). \
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

        switch await api.apiVersion {
        case .v3:
            do {
                try await api.markPrivateMessageAsRead(privateMessageID: privateMessageId, read: read)
            } catch {
                logger.error("""
                    Mark private message as read failed. privateMessageId=\(privateMessageId, privacy: .public). \
                    \(String(describing: error), privacy: .public)
                    """)
                throw LemmyServiceError(from: error)
            }

        case .v4:
            // v4 marks a private-message notification read by its unified
            // notification id, but the DM conversation store keys messages by
            // `PrivateMessageID` and `IncomingPrivateMessage` does not carry the
            // notification id (the neutral fetch dropped it — see
            // PrivateMessageImporter). So per-message server read-sync is not
            // expressible on v4 without threading the notification id through the
            // conversation model; that is a follow-up. The DM thread still clears
            // the unread dot locally (`setPrivateMessageRead`), and
            // `markAllInboxAsRead` clears private-message read state on the server
            // in bulk. Skip the server push here rather than throwing.
            logger.debug("""
                Skipping per-message server mark-read on a v4 instance \
                (notification id not carried; markAllInboxAsRead covers bulk clear).
                """)
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

        switch await api.apiVersion {
        case .v3:
            // v3's markAllAsRead only covers replies + mentions; private messages
            // must be marked individually. Fetch the unread messages and mark
            // each, then call markAllAsRead for the comment-based items.
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

        case .v4:
            // v4's unified inbox marks every kind read in one call — including
            // private messages, unlike v3's replies/mentions-only markAllAsRead.
            do {
                try await api.markAllNotificationsAsReadNeutral()
            } catch {
                logger.error("""
                    Mark all inbox failed. \
                    \(String(describing: error), privacy: .public)
                    """)
                throw LemmyServiceError(from: error)
            }
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

private extension LemmyService {
    /// Maps a 1-based inbox page number to the neutral list's opaque cursor: page
    /// 1 (or lower) is the first page (nil cursor); higher pages carry the number
    /// as the cursor value ("N"), matching the v3 backend's stringly page cursor.
    /// The unified inbox paginates opaquely, so this is a best-effort bridge from
    /// Spud's page-numbered inbox callers (which only ever request page 1 today).
    static func inboxCursor(forPage page: Int64) -> Cursor? {
        page <= 1 ? nil : Cursor(rawValue: String(page))
    }
}

private extension InboxCommentNotification {
    /// Maps a v3 `CommentReplyView` (from `getReplies`) into the neutral item,
    /// marked read by its `CommentReplyID`.
    init(reply view: Lemmy.CommentReplyView) {
        self.init(
            readReference: .commentReply(view.comment_reply.id),
            serverCommentId: view.comment.id,
            serverPostId: view.post.id,
            serverPersonId: view.creator.id,
            creatorName: view.creator.display_name ?? view.creator.name,
            content: view.comment.content,
            postTitle: view.post.name,
            communityName: view.community.name,
            score: view.counts.score,
            published: view.comment.published,
            isRead: view.comment_reply.read
        )
    }

    /// Maps a v3 `PersonMentionView` (from `getPersonMentions`) into the neutral
    /// item, marked read by its `PersonMentionID`.
    init(mention view: Lemmy.PersonMentionView) {
        self.init(
            readReference: .personMention(view.person_mention.id),
            serverCommentId: view.comment.id,
            serverPostId: view.post.id,
            serverPersonId: view.creator.id,
            creatorName: view.creator.display_name ?? view.creator.name,
            content: view.comment.content,
            postTitle: view.post.name,
            communityName: view.community.name,
            score: view.counts.score,
            published: view.comment.published,
            isRead: view.person_mention.read
        )
    }

    /// Maps a v4 unified-inbox `NotificationView` whose payload is a comment (a
    /// reply or mention) into the neutral item, marked read by its notification
    /// id. Returns nil for a non-comment payload or a notification missing its id
    /// (neither is expected for a v4 reply/mention, which always carry both).
    init?(notification: NotificationView) {
        guard
            let notificationId = notification.notification.id,
            case let .comment(view) = notification.data
        else {
            return nil
        }
        self.init(
            readReference: .notification(notificationId),
            serverCommentId: Lemmy.CommentID(view.comment.id),
            serverPostId: Lemmy.PostID(view.post.id),
            serverPersonId: Lemmy.PersonID(view.creator.id),
            creatorName: view.creator.displayName ?? view.creator.name,
            content: view.comment.content,
            postTitle: view.post.name,
            communityName: view.community.name,
            score: view.comment.score,
            published: view.comment.publishedAt,
            isRead: notification.notification.isRead
        )
    }
}
