//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import SpudDataKit
@testable import Spud

/// Recording double for `PostDetailLemmyServicing`, used by
/// `PostDetailViewModelMutationTests` to assert the view model's dispatch
/// methods forward the exact server ids / arguments to the service.
///
/// `@MainActor` so it can be driven from the `@MainActor` view model and its
/// suite; it satisfies the `Sendable` protocol's `async` requirements via an
/// isolated conformance (the caller awaits and hops to the main actor).
///
/// The double records only *successful* dispatches: when `errorToThrow` is set,
/// each throwing method throws it BEFORE appending an invocation, so a rethrow
/// test can assert both that the error propagates and that nothing was recorded.
///
/// Grows one call-site group at a time alongside `PostDetailLemmyServicing`.
@MainActor
final class RecordingPostDetailLemmyService: PostDetailLemmyServicing {
    enum Invocation: Equatable {
        case reportPost(serverPostId: Lemmy.PostID, reason: String)
        case reportComment(serverCommentId: Lemmy.CommentID, reason: String)
        case deleteComment(serverCommentId: Lemmy.CommentID, deleted: Bool)
        case deletePost(serverPostId: Lemmy.PostID, deleted: Bool)
        case removePost(serverPostId: Lemmy.PostID, removed: Bool, reason: String?)
        case lockPost(serverPostId: Lemmy.PostID, locked: Bool)
        case featurePost(serverPostId: Lemmy.PostID, featured: Bool, local: Bool)
        case removeComment(serverCommentId: Lemmy.CommentID, removed: Bool, reason: String?)
        case distinguishComment(serverCommentId: Lemmy.CommentID, distinguished: Bool)
        case banFromCommunity(
            serverCommunityId: Lemmy.CommunityID,
            serverPersonId: Lemmy.PersonID,
            ban: Bool,
            removeData: Bool,
            reason: String?
        )
        case retryComposition(clientToken: String)
        case discardComposition(clientToken: String)
        case setBlocked(serverPersonId: Lemmy.PersonID, blocked: Bool)
        case markAsRead(serverPostId: Lemmy.PostID)
        case fetchPostInfo(serverPostId: Lemmy.PostID)
        case fetchModerationCapability
        case vote(serverCommentId: Lemmy.CommentID, action: VoteStatus.Action)
        case setSaved(serverCommentId: Lemmy.CommentID, saved: Bool)
    }

    private(set) var invocations: [Invocation] = []

    /// When non-nil, every throwing method throws this instead of recording,
    /// exercising the view model's rethrow paths.
    var errorToThrow: (any Error)?

    /// The capability `fetchModerationCapability()` returns when it does not
    /// throw. Defaults to `.none`; a forwarding test sets it to assert the view
    /// model returns the service's value unchanged.
    var moderationCapabilityToReturn: ModerationCapability = .none

    func reportPost(serverPostId: Lemmy.PostID, reason: String) async throws {
        if let errorToThrow { throw errorToThrow }
        invocations.append(.reportPost(serverPostId: serverPostId, reason: reason))
    }

    func reportComment(serverCommentId: Lemmy.CommentID, reason: String) async throws {
        if let errorToThrow { throw errorToThrow }
        invocations.append(.reportComment(serverCommentId: serverCommentId, reason: reason))
    }

    func deleteComment(serverCommentId: Lemmy.CommentID, deleted: Bool) async throws {
        if let errorToThrow { throw errorToThrow }
        invocations.append(.deleteComment(serverCommentId: serverCommentId, deleted: deleted))
    }

    func deletePost(serverPostId: Lemmy.PostID, deleted: Bool) async throws {
        if let errorToThrow { throw errorToThrow }
        invocations.append(.deletePost(serverPostId: serverPostId, deleted: deleted))
    }

    func removePost(serverPostId: Lemmy.PostID, removed: Bool, reason: String?) async throws {
        if let errorToThrow { throw errorToThrow }
        invocations.append(.removePost(serverPostId: serverPostId, removed: removed, reason: reason))
    }

    func lockPost(serverPostId: Lemmy.PostID, locked: Bool) async throws {
        if let errorToThrow { throw errorToThrow }
        invocations.append(.lockPost(serverPostId: serverPostId, locked: locked))
    }

    func featurePost(serverPostId: Lemmy.PostID, featured: Bool, local: Bool) async throws {
        if let errorToThrow { throw errorToThrow }
        invocations.append(.featurePost(serverPostId: serverPostId, featured: featured, local: local))
    }

    func removeComment(serverCommentId: Lemmy.CommentID, removed: Bool, reason: String?) async throws {
        if let errorToThrow { throw errorToThrow }
        invocations.append(.removeComment(serverCommentId: serverCommentId, removed: removed, reason: reason))
    }

    func distinguishComment(serverCommentId: Lemmy.CommentID, distinguished: Bool) async throws {
        if let errorToThrow { throw errorToThrow }
        invocations.append(.distinguishComment(serverCommentId: serverCommentId, distinguished: distinguished))
    }

    func banFromCommunity(
        serverCommunityId: Lemmy.CommunityID,
        serverPersonId: Lemmy.PersonID,
        ban: Bool,
        removeData: Bool,
        reason: String?
    ) async throws {
        if let errorToThrow { throw errorToThrow }
        invocations.append(.banFromCommunity(
            serverCommunityId: serverCommunityId,
            serverPersonId: serverPersonId,
            ban: ban,
            removeData: removeData,
            reason: reason
        ))
    }

    /// `retryComposition`/`discardComposition` are non-throwing in the protocol
    /// (mirroring `LemmyServiceType`), so unlike the throwing methods above they
    /// record unconditionally — there is no `errorToThrow` path to exercise.
    func retryComposition(clientToken: String) async {
        invocations.append(.retryComposition(clientToken: clientToken))
    }

    func discardComposition(clientToken: String) async {
        invocations.append(.discardComposition(clientToken: clientToken))
    }

    func setBlocked(serverPersonId: Lemmy.PersonID, blocked: Bool) async throws {
        if let errorToThrow { throw errorToThrow }
        invocations.append(.setBlocked(serverPersonId: serverPersonId, blocked: blocked))
    }

    func markAsRead(serverPostId: Lemmy.PostID) async throws {
        if let errorToThrow { throw errorToThrow }
        invocations.append(.markAsRead(serverPostId: serverPostId))
    }

    func fetchPostInfo(serverPostId: Lemmy.PostID) async throws {
        if let errorToThrow { throw errorToThrow }
        invocations.append(.fetchPostInfo(serverPostId: serverPostId))
    }

    func fetchModerationCapability() async throws -> ModerationCapability {
        if let errorToThrow { throw errorToThrow }
        invocations.append(.fetchModerationCapability)
        return moderationCapabilityToReturn
    }

    func vote(serverCommentId: Lemmy.CommentID, vote action: VoteStatus.Action) async throws {
        if let errorToThrow { throw errorToThrow }
        invocations.append(.vote(serverCommentId: serverCommentId, action: action))
    }

    func setSaved(serverCommentId: Lemmy.CommentID, saved: Bool) async throws {
        if let errorToThrow { throw errorToThrow }
        invocations.append(.setSaved(serverCommentId: serverCommentId, saved: saved))
    }
}
