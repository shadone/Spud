//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Builds the canonical browser/share URL for a post or comment.
///
/// `.originalInstance` prefers the federation permalink (`ap_id`) carried on the
/// row and falls back to `<home>/post|comment/<id>`. `.myInstance` always uses
/// the account's home instance, ignoring the `ap_id`.
enum LinkURL {
    static func forPost(
        instance: Preferences.LinkInstance,
        originalPostUrl: String?,
        serverPostId: Int64,
        instanceActorId: String?
    ) -> URL? {
        url(
            instance: instance,
            preferred: originalPostUrl,
            instanceActorId: instanceActorId,
            path: "post/\(serverPostId)"
        )
    }

    static func forComment(
        instance: Preferences.LinkInstance,
        originalCommentUrl: String?,
        serverCommentId: Int64,
        instanceActorId: String?
    ) -> URL? {
        url(
            instance: instance,
            preferred: originalCommentUrl,
            instanceActorId: instanceActorId,
            path: "comment/\(serverCommentId)"
        )
    }

    private static func url(
        instance: Preferences.LinkInstance,
        preferred: String?,
        instanceActorId: String?,
        path: String
    ) -> URL? {
        // Original Instance with a usable ap_id wins; everything else
        // (My Instance, or Original Instance with no/invalid ap_id) uses home.
        if
            instance == .originalInstance,
            let preferred,
            !preferred.isEmpty,
            let url = URL(string: preferred)
        {
            return url
        }
        guard
            let instanceActorId,
            let instanceUrl = URL(string: instanceActorId)
        else { return nil }
        return instanceUrl.appending(path: path)
    }
}
