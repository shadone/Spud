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
    func reportPost(serverPostId: Lemmy.PostID, reason: String) async throws
    func reportComment(serverCommentId: Lemmy.CommentID, reason: String) async throws
    func deleteComment(serverCommentId: Lemmy.CommentID, deleted: Bool) async throws
    func deletePost(serverPostId: Lemmy.PostID, deleted: Bool) async throws
    func removePost(serverPostId: Lemmy.PostID, removed: Bool, reason: String?) async throws
    func lockPost(serverPostId: Lemmy.PostID, locked: Bool) async throws
    func featurePost(serverPostId: Lemmy.PostID, featured: Bool, local: Bool) async throws
    func removeComment(serverCommentId: Lemmy.CommentID, removed: Bool, reason: String?) async throws
    func distinguishComment(serverCommentId: Lemmy.CommentID, distinguished: Bool) async throws
    func banFromCommunity(
        serverCommunityId: Lemmy.CommunityID,
        serverPersonId: Lemmy.PersonID,
        ban: Bool,
        removeData: Bool,
        reason: String?
    ) async throws
    func retryComposition(clientToken: String) async
    func discardComposition(clientToken: String) async
    func setBlocked(serverPersonId: Lemmy.PersonID, blocked: Bool) async throws
    func markAsRead(serverPostId: Lemmy.PostID) async throws
    func fetchPostInfo(serverPostId: Lemmy.PostID) async throws
    func fetchModerationCapability() async throws -> ModerationCapability
    func vote(serverCommentId: Lemmy.CommentID, vote action: VoteStatus.Action) async throws
    func setSaved(serverCommentId: Lemmy.CommentID, saved: Bool) async throws
}

/// Production conformance: forwards to the account's `LemmyServiceType` actor.
///
/// `PostDetailViewModel` builds one of these from `accountScope.lemmyService`
/// when no test double is injected, so the live path is an unconditional
/// one-line forward per requirement.
struct PostDetailLemmyServiceAdapter: PostDetailLemmyServicing {
    let lemmyService: any LemmyServiceType

    func reportPost(serverPostId: Lemmy.PostID, reason: String) async throws {
        try await lemmyService.reportPost(serverPostId: serverPostId, reason: reason)
    }

    func reportComment(serverCommentId: Lemmy.CommentID, reason: String) async throws {
        try await lemmyService.reportComment(serverCommentId: serverCommentId, reason: reason)
    }

    func deleteComment(serverCommentId: Lemmy.CommentID, deleted: Bool) async throws {
        try await lemmyService.deleteComment(serverCommentId: serverCommentId, deleted: deleted)
    }

    func deletePost(serverPostId: Lemmy.PostID, deleted: Bool) async throws {
        try await lemmyService.deletePost(serverPostId: serverPostId, deleted: deleted)
    }

    func removePost(serverPostId: Lemmy.PostID, removed: Bool, reason: String?) async throws {
        try await lemmyService.removePost(serverPostId: serverPostId, removed: removed, reason: reason)
    }

    func lockPost(serverPostId: Lemmy.PostID, locked: Bool) async throws {
        try await lemmyService.lockPost(serverPostId: serverPostId, locked: locked)
    }

    func featurePost(serverPostId: Lemmy.PostID, featured: Bool, local: Bool) async throws {
        try await lemmyService.featurePost(serverPostId: serverPostId, featured: featured, local: local)
    }

    func removeComment(serverCommentId: Lemmy.CommentID, removed: Bool, reason: String?) async throws {
        try await lemmyService.removeComment(serverCommentId: serverCommentId, removed: removed, reason: reason)
    }

    func distinguishComment(serverCommentId: Lemmy.CommentID, distinguished: Bool) async throws {
        try await lemmyService.distinguishComment(serverCommentId: serverCommentId, distinguished: distinguished)
    }

    func banFromCommunity(
        serverCommunityId: Lemmy.CommunityID,
        serverPersonId: Lemmy.PersonID,
        ban: Bool,
        removeData: Bool,
        reason: String?
    ) async throws {
        try await lemmyService.banFromCommunity(
            serverCommunityId: serverCommunityId,
            serverPersonId: serverPersonId,
            ban: ban,
            removeData: removeData,
            reason: reason
        )
    }

    func retryComposition(clientToken: String) async {
        await lemmyService.retryComposition(clientToken: clientToken)
    }

    func discardComposition(clientToken: String) async {
        await lemmyService.discardComposition(clientToken: clientToken)
    }

    func setBlocked(serverPersonId: Lemmy.PersonID, blocked: Bool) async throws {
        try await lemmyService.setBlocked(serverPersonId: serverPersonId, blocked: blocked)
    }

    func markAsRead(serverPostId: Lemmy.PostID) async throws {
        try await lemmyService.markAsRead(serverPostId: serverPostId)
    }

    func fetchPostInfo(serverPostId: Lemmy.PostID) async throws {
        try await lemmyService.fetchPostInfo(serverPostId: serverPostId)
    }

    func fetchModerationCapability() async throws -> ModerationCapability {
        try await lemmyService.fetchModerationCapability()
    }

    func vote(serverCommentId: Lemmy.CommentID, vote action: VoteStatus.Action) async throws {
        try await lemmyService.vote(serverCommentId: serverCommentId, vote: action)
    }

    func setSaved(serverCommentId: Lemmy.CommentID, saved: Bool) async throws {
        try await lemmyService.setSaved(serverCommentId: serverCommentId, saved: saved)
    }
}
