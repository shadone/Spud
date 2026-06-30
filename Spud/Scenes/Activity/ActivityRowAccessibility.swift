//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit

/// Builds the single, composed VoiceOver label for an activity row so the whole
/// cell reads as one natural utterance - e.g. "You upvoted, 2h ago, <post title>,
/// in <community>, 248 points, 19 comments" - rather than letting VoiceOver land
/// on the verb chip, the score glyphs (which it reads as "black up-pointing
/// triangle"), and the body separately.
enum ActivityRowAccessibility {
    /// Composes the row label for a post activity. `postSummary` is the reused
    /// `PostListPostViewModel.accessibilityLabel` (title, community, score,
    /// comments, saved/locked/pinned), which already reads cleanly.
    static func postLabel(act: ActivityAct, occurredAt: Date, postSummary: String) -> String {
        [act.accessibilityVerb, occurredAt.activityRelativeString, postSummary]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    /// Composes the row label for a comment activity from the comment's body, its
    /// parent post, community, and score.
    static func commentLabel(act: ActivityAct, occurredAt: Date, comment: ActivityCommentRow) -> String {
        var parts: [String] = [act.accessibilityVerb, occurredAt.activityRelativeString]

        let trimmedBody = comment.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBody.isEmpty {
            parts.append(String(
                format: NSLocalizedString("comment: %@", comment: "Activity VoiceOver: a comment body"),
                trimmedBody
            ))
        }
        if !comment.parentPostTitle.isEmpty {
            parts.append(String(
                format: NSLocalizedString("on %@", comment: "Activity VoiceOver: the parent post a comment is on"),
                comment.parentPostTitle
            ))
        }
        if !comment.communityName.isEmpty {
            parts.append(String(
                format: NSLocalizedString("in %@", comment: "Activity VoiceOver: the community a comment belongs to"),
                comment.communityName
            ))
        }
        parts.append(String(
            format: NSLocalizedString("score %lld", comment: "Activity VoiceOver: a comment's score"),
            comment.score
        ))

        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
