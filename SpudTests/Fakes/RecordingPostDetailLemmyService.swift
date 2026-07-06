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
}
