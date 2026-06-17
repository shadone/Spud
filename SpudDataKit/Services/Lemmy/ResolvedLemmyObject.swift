//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudUtilKit

/// App-facing result of a Lemmy `resolve_object` call, already mapped to local
/// ids valid for the account the resolve ran under.
public enum ResolvedLemmyObject: Sendable {
    /// A resolved post, by local id under the resolving account's instance.
    case post(postId: Components.Schemas.PostID, instance: InstanceActorId)
    /// A resolved community, by name + its home instance (federation-aware
    /// loaders re-fetch by qualified name, so this stays name-based).
    case community(name: String, instance: InstanceActorId)
    /// A resolved person, by local id under the resolving account's instance.
    case person(personId: Components.Schemas.PersonID, instance: InstanceActorId)
    /// A resolved comment, by its parent post id + comment id, both local under
    /// the resolving account's instance. Callers open the post and scroll to the
    /// comment.
    case comment(
        postId: Components.Schemas.PostID,
        commentId: Components.Schemas.CommentID,
        instance: InstanceActorId
    )
    /// Nothing resolved (not federated, unknown, or empty response).
    case unresolved

    public init(
        response: Components.Schemas.ResolveObjectResponse,
        homeInstance: InstanceActorId
    ) {
        if let post = response.post {
            self = .post(postId: post.post.id, instance: homeInstance)
        } else if let community = response.community {
            let instance = InstanceActorId(from: community.community.actor_id) ?? homeInstance
            self = .community(name: community.community.name, instance: instance)
        } else if let person = response.person {
            self = .person(personId: person.person.id, instance: homeInstance)
        } else if let comment = response.comment {
            self = .comment(
                postId: comment.comment.post_id,
                commentId: comment.comment.id,
                instance: homeInstance
            )
        } else {
            self = .unresolved
        }
    }
}
