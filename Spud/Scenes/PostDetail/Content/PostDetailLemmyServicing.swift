//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import SpudDataKit

/// The subset of `LemmyServiceType` the post-detail scene drives, seamed so
/// `PostDetailViewModel`'s dispatch methods are unit-testable from SpudTests
/// (which cannot import SpudDataKitTests' RecordingLemmyService).
///
/// Signatures mirror `LemmyServiceType` (SpudDataKit/Services/Lemmy/LemmyService.swift)
/// exactly. The protocol grows one call-site group at a time as the PostDetail
/// Phase 3 migration proceeds; add only the methods a task moves.
protocol PostDetailLemmyServicing: Sendable {
    func reportPost(serverPostId: Components.Schemas.PostID, reason: String) async throws
    func reportComment(serverCommentId: Components.Schemas.CommentID, reason: String) async throws
    func deleteComment(serverCommentId: Components.Schemas.CommentID, deleted: Bool) async throws
    func deletePost(serverPostId: Components.Schemas.PostID, deleted: Bool) async throws
}

/// Production conformance: forwards to the account's `LemmyServiceType` actor.
///
/// `PostDetailViewModel` builds one of these from `accountScope.lemmyService`
/// when no test double is injected, so the live path is an unconditional
/// one-line forward per requirement.
struct PostDetailLemmyServiceAdapter: PostDetailLemmyServicing {
    let lemmyService: any LemmyServiceType

    func reportPost(serverPostId: Components.Schemas.PostID, reason: String) async throws {
        try await lemmyService.reportPost(serverPostId: serverPostId, reason: reason)
    }

    func reportComment(serverCommentId: Components.Schemas.CommentID, reason: String) async throws {
        try await lemmyService.reportComment(serverCommentId: serverCommentId, reason: reason)
    }

    func deleteComment(serverCommentId: Components.Schemas.CommentID, deleted: Bool) async throws {
        try await lemmyService.deleteComment(serverCommentId: serverCommentId, deleted: deleted)
    }

    func deletePost(serverPostId: Components.Schemas.PostID, deleted: Bool) async throws {
        try await lemmyService.deletePost(serverPostId: serverPostId, deleted: deleted)
    }
}
