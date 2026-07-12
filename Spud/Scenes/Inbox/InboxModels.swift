//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudDataKit
import SpudUtilKit

/// A single inbox reply: someone replied to one of the account holder's posts
/// or comments. Carries the server post id so a tap can open PostDetail, and a
/// backend-neutral read reference so it can be marked read on whichever API
/// produced it (see `InboxItemReadReference`).
///
/// Built from the version-neutral `InboxCommentNotification` the service returns,
/// so it renders identically whether the reply came from a v3 (`getReplies`) or
/// v4 (unified notification inbox) backend.
struct InboxReplyItem: Hashable, Identifiable {
    let readReference: InboxItemReadReference
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

    var id: InboxItemReadReference {
        readReference
    }

    /// Returns a copy with `isRead` set, for optimistic local updates.
    func markedRead() -> InboxReplyItem {
        var copy = self
        copy.isRead = true
        return copy
    }

    init(_ notification: InboxCommentNotification) {
        readReference = notification.readReference
        serverCommentId = notification.serverCommentId
        serverPostId = notification.serverPostId
        serverPersonId = notification.serverPersonId
        creatorName = notification.creatorName
        content = notification.content
        postTitle = notification.postTitle
        communityName = notification.communityName
        score = notification.score
        published = notification.published
        isRead = notification.isRead
    }
}

/// A single inbox mention: someone @-mentioned the account holder in a comment.
/// Built from the same version-neutral `InboxCommentNotification` as
/// `InboxReplyItem`; the two differ only in which fetch (mentions vs replies)
/// produced them.
struct InboxMentionItem: Hashable, Identifiable {
    let readReference: InboxItemReadReference
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

    var id: InboxItemReadReference {
        readReference
    }

    /// Returns a copy with `isRead` set, for optimistic local updates.
    func markedRead() -> InboxMentionItem {
        var copy = self
        copy.isRead = true
        return copy
    }

    init(_ notification: InboxCommentNotification) {
        readReference = notification.readReference
        serverCommentId = notification.serverCommentId
        serverPostId = notification.serverPostId
        serverPersonId = notification.serverPersonId
        creatorName = notification.creatorName
        content = notification.content
        postTitle = notification.postTitle
        communityName = notification.communityName
        score = notification.score
        published = notification.published
        isRead = notification.isRead
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
