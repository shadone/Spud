//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
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
        case reportPost(serverPostId: Components.Schemas.PostID, reason: String)
        case reportComment(serverCommentId: Components.Schemas.CommentID, reason: String)
        case deleteComment(serverCommentId: Components.Schemas.CommentID, deleted: Bool)
        case deletePost(serverPostId: Components.Schemas.PostID, deleted: Bool)
        case removePost(serverPostId: Components.Schemas.PostID, removed: Bool, reason: String?)
        case lockPost(serverPostId: Components.Schemas.PostID, locked: Bool)
        case featurePost(serverPostId: Components.Schemas.PostID, featured: Bool, local: Bool)
        case removeComment(serverCommentId: Components.Schemas.CommentID, removed: Bool, reason: String?)
        case distinguishComment(serverCommentId: Components.Schemas.CommentID, distinguished: Bool)
        case banFromCommunity(
            serverCommunityId: Components.Schemas.CommunityID,
            serverPersonId: Components.Schemas.PersonID,
            ban: Bool,
            removeData: Bool,
            reason: String?
        )
    }

    private(set) var invocations: [Invocation] = []

    /// When non-nil, every throwing method throws this instead of recording,
    /// exercising the view model's rethrow paths.
    var errorToThrow: (any Error)?

    func reportPost(serverPostId: Components.Schemas.PostID, reason: String) async throws {
        if let errorToThrow { throw errorToThrow }
        invocations.append(.reportPost(serverPostId: serverPostId, reason: reason))
    }

    func reportComment(serverCommentId: Components.Schemas.CommentID, reason: String) async throws {
        if let errorToThrow { throw errorToThrow }
        invocations.append(.reportComment(serverCommentId: serverCommentId, reason: reason))
    }

    func deleteComment(serverCommentId: Components.Schemas.CommentID, deleted: Bool) async throws {
        if let errorToThrow { throw errorToThrow }
        invocations.append(.deleteComment(serverCommentId: serverCommentId, deleted: deleted))
    }

    func deletePost(serverPostId: Components.Schemas.PostID, deleted: Bool) async throws {
        if let errorToThrow { throw errorToThrow }
        invocations.append(.deletePost(serverPostId: serverPostId, deleted: deleted))
    }

    func removePost(serverPostId: Components.Schemas.PostID, removed: Bool, reason: String?) async throws {
        if let errorToThrow { throw errorToThrow }
        invocations.append(.removePost(serverPostId: serverPostId, removed: removed, reason: reason))
    }

    func lockPost(serverPostId: Components.Schemas.PostID, locked: Bool) async throws {
        if let errorToThrow { throw errorToThrow }
        invocations.append(.lockPost(serverPostId: serverPostId, locked: locked))
    }

    func featurePost(serverPostId: Components.Schemas.PostID, featured: Bool, local: Bool) async throws {
        if let errorToThrow { throw errorToThrow }
        invocations.append(.featurePost(serverPostId: serverPostId, featured: featured, local: local))
    }

    func removeComment(serverCommentId: Components.Schemas.CommentID, removed: Bool, reason: String?) async throws {
        if let errorToThrow { throw errorToThrow }
        invocations.append(.removeComment(serverCommentId: serverCommentId, removed: removed, reason: reason))
    }

    func distinguishComment(serverCommentId: Components.Schemas.CommentID, distinguished: Bool) async throws {
        if let errorToThrow { throw errorToThrow }
        invocations.append(.distinguishComment(serverCommentId: serverCommentId, distinguished: distinguished))
    }

    func banFromCommunity(
        serverCommunityId: Components.Schemas.CommunityID,
        serverPersonId: Components.Schemas.PersonID,
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
}
