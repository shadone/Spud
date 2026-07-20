//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Single source of truth for whether a user may comment on a post, and for the
/// user-facing copy that explains a locked post. A locked post rejects new
/// comments/replies server-side (`LemmyErrorType::Locked`); voting on the post
/// and its comments, and editing your own comment, remain allowed. Centralised
/// here so every gate and every label reads the same rule and the same wording.
enum CommentLockPolicy {
    /// Whether a new comment or reply may be started. Editing an existing
    /// comment is a separate, always-allowed action and is NOT gated by this.
    static func canComment(isPostLocked: Bool) -> Bool {
        !isPostLocked
    }

    /// Title for the locked-comments notice / gate ("Comments are locked").
    static var title: String {
        NSLocalizedString(
            "Comments are locked",
            comment: "Title shown when a post is locked and cannot receive new comments."
        )
    }

    /// Explanatory subtitle: new comments are off, but voting still works.
    static var message: String {
        NSLocalizedString(
            "New comments and replies are turned off. You can still vote.",
            comment: "Explains that a locked post accepts no new comments but voting is still allowed."
        )
    }

    /// Short status word for compact labels and VoiceOver ("Locked").
    static var shortStatus: String {
        NSLocalizedString(
            "Locked",
            comment: "Short status label for a locked post."
        )
    }
}
