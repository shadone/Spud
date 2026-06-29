//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB

/// Which kind of content a row will create.
public enum OutboundKind: Int64, Codable, Sendable {
    case comment = 0
    case post = 1
    /// A private (direct) message. Carries only a `body` and a
    /// `recipientServerPersonId`; all the comment/post fields are nil.
    case directMessage = 2
}

/// Lifecycle of an outbound row. There is no `sent` — a successful send deletes
/// the row (the real content lives in `comment`/`post`).
public enum OutboundStatus: Int64, Codable, Sendable {
    case draft = 0
    case queued = 1
    case sending = 2
    case failed = 3
}

/// The mutable inputs a composer collects, independent of send bookkeeping.
public struct OutboundDraftInput: Sendable, Equatable {
    public var kind: OutboundKind
    public var body: String
    public var postServerId: Int64?
    public var parentCommentServerId: Int64?
    public var communityServerId: Int64?
    public var title: String?
    public var url: String?
    public var nsfw: Bool
    public var postType: Int64
    /// nil = create a new comment/post. When set, this row EDITS the comment with
    /// that server id (the performer calls `editComment` and the create-dedup is
    /// skipped). Only meaningful for `.comment`.
    public var editCommentServerId: Int64?
    /// nil = create a new post. When set, this row EDITS the post with that server
    /// id (the performer calls `editPost` and the create-dedup is skipped). Only
    /// meaningful for `.post`.
    public var editPostServerId: Int64?
    /// Server person id of the recipient for a `.directMessage` row. nil for
    /// `.comment` / `.post` (a DM carries only a body + recipient).
    public var recipientServerPersonId: Int64?

    public init(
        kind: OutboundKind, body: String, postServerId: Int64?, parentCommentServerId: Int64?,
        communityServerId: Int64?, title: String?, url: String?, nsfw: Bool, postType: Int64,
        editCommentServerId: Int64? = nil, editPostServerId: Int64? = nil,
        recipientServerPersonId: Int64? = nil
    ) {
        self.kind = kind
        self.body = body
        self.postServerId = postServerId
        self.parentCommentServerId = parentCommentServerId
        self.communityServerId = communityServerId
        self.title = title
        self.url = url
        self.nsfw = nsfw
        self.postType = postType
        self.editCommentServerId = editCommentServerId
        self.editPostServerId = editPostServerId
        self.recipientServerPersonId = recipientServerPersonId
    }
}

/// A persisted draft / in-flight / failed composition (comment or post).
public struct OutboundContentRecord: Codable, FetchableRecord, MutablePersistableRecord, Sendable, Equatable {
    public var id: Int64?
    public var clientToken: String
    public var accountId: Int64
    public var kind: Int64
    public var status: Int64
    public var draftKey: String
    public var body: String
    public var postServerId: Int64?
    public var parentCommentServerId: Int64?
    public var communityServerId: Int64?
    public var title: String?
    public var url: String?
    public var nsfw: Bool
    public var postType: Int64
    /// nil = create a new comment. When set, this row EDITS the comment with that
    /// server id: the performer calls `editComment(commentId:content:)` and the
    /// create-dedup is skipped. Persisted by the `v21_outboundEditComment`
    /// migration.
    public var editCommentServerId: Int64?
    /// nil = create a new post. When set, this row EDITS the post with that server
    /// id: the performer calls `editPost(postID:...)` and the create-dedup is
    /// skipped. Persisted by the `v22_outboundEditPost` migration.
    public var editPostServerId: Int64?
    /// Server person id of the recipient for a `.directMessage` row; nil for
    /// `.comment` / `.post`. Persisted by the `v24_outboundDirectMessage`
    /// migration as a nullable column.
    public var recipientServerPersonId: Int64?
    public var attempts: Int64
    public var lastError: String?
    public var nextAttemptAt: Double?
    public var createdAt: Double
    public var updatedAt: Double

    public static let databaseTableName = "outboundContent"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public static func commentDraftKey(postServerId: Int64, parentCommentServerId: Int64?) -> String {
        "c:\(postServerId):\(parentCommentServerId.map(String.init) ?? "0")"
    }

    public static func postDraftKey(communityServerId: Int64?) -> String {
        "p:\(communityServerId.map(String.init) ?? "0")"
    }

    /// Draft key for an EDIT of an existing comment. Keyed by the edited comment's
    /// server id so it never coalesces with a reply draft for the same post/parent
    /// (those use `commentDraftKey`): opening Edit must not load or clobber a
    /// pending reply, and vice versa.
    public static func editCommentDraftKey(serverCommentId: Int64) -> String {
        "ec:\(serverCommentId)"
    }

    /// Draft key for an EDIT of an existing post. Keyed by the edited post's server
    /// id so it never coalesces with a new-post draft for the same community (those
    /// use `postDraftKey`): opening Edit must not load or clobber a pending new-post
    /// draft, and vice versa.
    public static func editPostDraftKey(serverPostId: Int64) -> String {
        "ep:\(serverPostId)"
    }

    /// Draft key for the per-recipient DM **autosave** draft — the single
    /// in-progress, unsent message text for one correspondent. There is exactly
    /// one such draft row per recipient (consistent with comment/post drafts),
    /// so opening a DM thread loads/overwrites this one row.
    ///
    /// This is deliberately distinct from `dmSendKey`: a *send* must coexist with
    /// other in-flight sends to the same recipient (see `dmSendKey`), whereas the
    /// autosave draft is a singleton per correspondent.
    public static func dmDraftKey(recipientServerPersonId: Int64) -> String {
        "dm:\(recipientServerPersonId)"
    }

    /// Unique draft key for a single queued/sending DM **send**. The
    /// `(accountId, draftKey)` unique index only constrains `status == draft`
    /// rows, but to let several messages to the *same* recipient be in flight at
    /// once (iMessage-like), each send gets a per-row key salted with its unique
    /// `clientToken`. This guarantees concurrent sends to one correspondent never
    /// collide on the draft index and each remains independently observable.
    public static func dmSendKey(recipientServerPersonId: Int64, clientToken: String) -> String {
        "dm:\(recipientServerPersonId):send:\(clientToken)"
    }

    public static func draftKey(for input: OutboundDraftInput) -> String {
        switch input.kind {
        case .comment:
            if let editCommentServerId = input.editCommentServerId {
                editCommentDraftKey(serverCommentId: editCommentServerId)
            } else {
                commentDraftKey(postServerId: input.postServerId ?? 0, parentCommentServerId: input.parentCommentServerId)
            }
        case .post:
            if let editPostServerId = input.editPostServerId {
                editPostDraftKey(serverPostId: editPostServerId)
            } else {
                postDraftKey(communityServerId: input.communityServerId)
            }
        case .directMessage:
            // The DM autosave draft is per-recipient. Sends use the unique
            // `dmSendKey` instead (assigned at enqueue time), so this only ever
            // keys the singleton draft row for the correspondent.
            dmDraftKey(forDraftInput: input)
        }
    }

    /// DM autosave draft key for `input`, with a debug-only invariant check that
    /// the recipient is present. A DM draft REQUIRES a recipient — the real send
    /// path always passes a non-optional one, so a nil here is a programmer error,
    /// not a valid input. Trap it in debug; release still falls through to the
    /// `?? 0` sentinel (rather than crash production), which would park a phantom
    /// `dm:0` slot — visible and recoverable, never silent data loss.
    private static func dmDraftKey(forDraftInput input: OutboundDraftInput) -> String {
        if input.recipientServerPersonId == nil {
            assertionFailure("DM draft requires a recipient; got nil recipientServerPersonId")
        }
        return dmDraftKey(recipientServerPersonId: input.recipientServerPersonId ?? 0)
    }
}
