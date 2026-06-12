//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudUtilKit

/// A single inbox reply: someone replied to one of the account holder's posts
/// or comments. Carries the server post id so a tap can open PostDetail, and
/// the comment-reply id so it can be marked read.
struct InboxReplyItem: Hashable, Identifiable {
    let commentReplyId: Components.Schemas.CommentReplyID
    let serverCommentId: Components.Schemas.CommentID
    let serverPostId: Components.Schemas.PostID
    let serverPersonId: Components.Schemas.PersonID
    let creatorName: String
    let content: String
    let postTitle: String
    let communityName: String
    let score: Int64
    let published: Date
    var isRead: Bool

    var id: Components.Schemas.CommentReplyID {
        commentReplyId
    }

    /// Returns a copy with `isRead` set, for optimistic local updates.
    func markedRead() -> InboxReplyItem {
        var copy = self
        copy.isRead = true
        return copy
    }

    init(view: Components.Schemas.CommentReplyView) {
        commentReplyId = view.comment_reply.id
        serverCommentId = view.comment.id
        serverPostId = view.post.id
        serverPersonId = view.creator.id
        creatorName = view.creator.display_name ?? view.creator.name
        content = view.comment.content
        postTitle = view.post.name
        communityName = view.community.name
        score = view.counts.score
        published = view.comment.published
        isRead = view.comment_reply.read
    }
}

/// A single inbox mention: someone @-mentioned the account holder in a comment.
struct InboxMentionItem: Hashable, Identifiable {
    let personMentionId: Components.Schemas.PersonMentionID
    let serverCommentId: Components.Schemas.CommentID
    let serverPostId: Components.Schemas.PostID
    let serverPersonId: Components.Schemas.PersonID
    let creatorName: String
    let content: String
    let postTitle: String
    let communityName: String
    let score: Int64
    let published: Date
    var isRead: Bool

    var id: Components.Schemas.PersonMentionID {
        personMentionId
    }

    /// Returns a copy with `isRead` set, for optimistic local updates.
    func markedRead() -> InboxMentionItem {
        var copy = self
        copy.isRead = true
        return copy
    }

    init(view: Components.Schemas.PersonMentionView) {
        personMentionId = view.person_mention.id
        serverCommentId = view.comment.id
        serverPostId = view.post.id
        serverPersonId = view.creator.id
        creatorName = view.creator.display_name ?? view.creator.name
        content = view.comment.content
        postTitle = view.post.name
        communityName = view.community.name
        score = view.counts.score
        published = view.comment.published
        isRead = view.person_mention.read
    }
}

/// A single private message, as it appears inside a DM thread.
struct InboxMessageItem: Hashable, Identifiable {
    let privateMessageId: Components.Schemas.PrivateMessageID
    let creatorId: Components.Schemas.PersonID
    let recipientId: Components.Schemas.PersonID
    let content: String
    let published: Date
    var isRead: Bool

    var id: Components.Schemas.PrivateMessageID {
        privateMessageId
    }

    init(view: Components.Schemas.PrivateMessageView) {
        privateMessageId = view.private_message.id
        creatorId = view.private_message.creator_id
        recipientId = view.private_message.recipient_id
        content = view.private_message.content
        published = view.private_message.published
        isRead = view.private_message.read
    }
}

/// A conversation grouping of private messages with a single other person.
/// Built by grouping the flat `getPrivateMessages` list by the correspondent
/// (the participant who is not the account holder).
struct InboxConversation: Hashable, Identifiable {
    let correspondentId: Components.Schemas.PersonID
    let correspondentName: String
    let correspondentAvatarUrl: URL?
    /// Most-recent message in the thread, for the preview row.
    let latestContent: String
    let latestPublished: Date
    /// Number of unread messages from the correspondent.
    let unreadCount: Int
    /// All messages in the thread, oldest first.
    let messages: [InboxMessageItem]

    var id: Components.Schemas.PersonID {
        correspondentId
    }

    var hasUnread: Bool {
        unreadCount > 0
    }
}

enum InboxConversationBuilder {
    /// Group a flat list of private-message views into per-correspondent
    /// conversations, newest-thread first. `myPersonId` identifies the account
    /// holder so the "other" participant can be resolved for each message.
    static func conversations(
        from views: [Components.Schemas.PrivateMessageView],
        myPersonId: Components.Schemas.PersonID?
    ) -> [InboxConversation] {
        struct Accum {
            var name: String
            var avatarUrl: URL?
            var items: [InboxMessageItem]
        }

        var byCorrespondent: [Components.Schemas.PersonID: Accum] = [:]

        for view in views {
            let message = InboxMessageItem(view: view)
            // The correspondent is whoever is not me. When myPersonId is
            // unknown, fall back to the creator (inbox messages are almost
            // always received, so creator is the other party).
            let correspondentIsCreator: Bool
            if let myPersonId {
                correspondentIsCreator = message.creatorId != myPersonId
            } else {
                correspondentIsCreator = true
            }
            let correspondentId = correspondentIsCreator ? message.creatorId : message.recipientId
            let correspondentPerson = correspondentIsCreator ? view.creator : view.recipient
            let name = correspondentPerson.display_name ?? correspondentPerson.name
            let avatarUrl = correspondentPerson.avatar.flatMap { URL(string: $0) }

            if byCorrespondent[correspondentId] == nil {
                byCorrespondent[correspondentId] = Accum(name: name, avatarUrl: avatarUrl, items: [])
            }
            byCorrespondent[correspondentId]?.items.append(message)
        }

        let conversations: [InboxConversation] = byCorrespondent.map { correspondentId, accum in
            let sorted = accum.items.sorted { $0.published < $1.published }
            let latest = sorted.last
            let unread = sorted.filter { !$0.isRead && $0.creatorId == correspondentId }.count
            return InboxConversation(
                correspondentId: correspondentId,
                correspondentName: accum.name,
                correspondentAvatarUrl: accum.avatarUrl,
                latestContent: latest?.content ?? "",
                latestPublished: latest?.published ?? .distantPast,
                unreadCount: unread,
                messages: sorted
            )
        }

        return conversations.sorted { $0.latestPublished > $1.latestPublished }
    }
}
