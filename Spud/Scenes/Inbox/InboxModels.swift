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
    let commentReplyId: Lemmy.CommentReplyID
    let serverCommentId: Lemmy.CommentID
    let serverPostId: Lemmy.PostID
    let serverPersonId: Lemmy.PersonID
    let creatorName: String
    let content: String
    let postTitle: String
    let communityName: String
    let score: Int64
    let published: Date
    var isRead: Bool

    var id: Lemmy.CommentReplyID {
        commentReplyId
    }

    /// Returns a copy with `isRead` set, for optimistic local updates.
    func markedRead() -> InboxReplyItem {
        var copy = self
        copy.isRead = true
        return copy
    }

    init(view: Lemmy.CommentReplyView) {
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
    let personMentionId: Lemmy.PersonMentionID
    let serverCommentId: Lemmy.CommentID
    let serverPostId: Lemmy.PostID
    let serverPersonId: Lemmy.PersonID
    let creatorName: String
    let content: String
    let postTitle: String
    let communityName: String
    let score: Int64
    let published: Date
    var isRead: Bool

    var id: Lemmy.PersonMentionID {
        personMentionId
    }

    /// Returns a copy with `isRead` set, for optimistic local updates.
    func markedRead() -> InboxMentionItem {
        var copy = self
        copy.isRead = true
        return copy
    }

    init(view: Lemmy.PersonMentionView) {
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

/// The optimistic-send state of a conversation row, derived from the account's
/// still-pending outbound DM rows for the correspondent (`ComposerOutboxService`).
/// `nil` means the conversation has no in-flight or failed outgoing message — the
/// common, fully-confirmed case.
enum InboxConversationPendingStatus: Hashable {
    /// One or more outgoing messages are queued/sending (none failed). The row
    /// shows a "Sending…" indicator.
    case sending
    /// At least one outgoing message permanently failed. Failed dominates so the
    /// user is alerted: the row shows "Not delivered".
    case failed
}

/// A conversation grouping of private messages with a single other person, as
/// rendered in the inbox Messages list.
///
/// Sourced from the persistent `privateMessage` store (`observeConversations`)
/// and MERGED with the account's still-pending outbound DM rows so the list
/// matches the iMessage feel: an existing thread shows a "Sending…"/"Not
/// delivered" indicator while a send is in flight/failed, and a brand-new
/// conversation (a first message to someone with no persisted server messages
/// yet) appears optimistically. Identified by the correspondent's server person
/// id, so a synthetic pending-only row collapses into the real thread once the
/// server copy lands. See `InboxConversationMerger`.
struct InboxConversation: Hashable, Identifiable {
    let correspondentId: Lemmy.PersonID
    let correspondentName: String
    let correspondentAvatarUrl: URL?
    /// Most-recent message in the thread (confirmed or optimistic), for the
    /// preview row.
    let latestContent: String
    let latestPublished: Date
    /// Number of unread incoming messages from the correspondent.
    let unreadCount: Int
    /// Optimistic-send state of the most recent outgoing message(s), or nil when
    /// nothing is in flight.
    let pendingStatus: InboxConversationPendingStatus?

    var id: Lemmy.PersonID {
        correspondentId
    }

    var hasUnread: Bool {
        unreadCount > 0
    }
}
