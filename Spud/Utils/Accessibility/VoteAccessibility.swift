//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit

/// Shared VoiceOver phrasing for vote score and state. Centralised so the post
/// cell, comment cell, and the post-detail vote buttons all read consistently.
enum VoteAccessibility {
    /// A natural-language description of a score plus the current vote, e.g.
    /// "42 points, upvoted". The numeric value is spoken in full (not the
    /// abbreviated "1.2K" the visible label uses).
    static func scoreLabel(score: Int64, voteStatus: VoteStatus) -> String {
        let points = String(
            format: NSLocalizedString("%lld points", comment: "VoiceOver: post or comment score"),
            score
        )
        switch voteStatus {
        case .up:
            return points + ", " + NSLocalizedString("upvoted", comment: "VoiceOver: vote state")
        case .down:
            return points + ", " + NSLocalizedString("downvoted", comment: "VoiceOver: vote state")
        case .neutral:
            return points
        }
    }

    /// State-aware label for the upvote button.
    static func upvoteButtonLabel(isUpvoted: Bool) -> String {
        isUpvoted
            ? NSLocalizedString("Remove upvote", comment: "VoiceOver: upvote button, already upvoted")
            : NSLocalizedString("Upvote", comment: "VoiceOver: upvote button")
    }

    /// State-aware label for the downvote button.
    static func downvoteButtonLabel(isDownvoted: Bool) -> String {
        isDownvoted
            ? NSLocalizedString("Remove downvote", comment: "VoiceOver: downvote button, already downvoted")
            : NSLocalizedString("Downvote", comment: "VoiceOver: downvote button")
    }

    /// State-aware label for the save button.
    static func saveButtonLabel(isSaved: Bool) -> String {
        isSaved
            ? NSLocalizedString("Unsave", comment: "VoiceOver: save button, already saved")
            : NSLocalizedString("Save", comment: "VoiceOver: save button")
    }
}

/// Shared VoiceOver phrasing for comment counts.
enum CommentsAccessibility {
    /// A natural-language comment count, e.g. "3 comments" / "1 comment".
    static func label(count: Int64) -> String {
        if count == 1 {
            return NSLocalizedString("1 comment", comment: "VoiceOver: single comment count")
        }
        return String(
            format: NSLocalizedString("%lld comments", comment: "VoiceOver: comment count"),
            count
        )
    }
}
