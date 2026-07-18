//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUtilKit

/// Builds the accessibility/alt-text description embedded in an exported
/// share-card PNG (`ShareCardImageRenderer.writePNG`) and set as the editor
/// preview's `accessibilityLabel`. Redaction-aware: when
/// `options.redactIdentities` is set, person handles are omitted from the
/// description exactly as they're redacted on the card itself — the
/// community is never redacted, on the card or here. Dates are always
/// absolute (`dateStyle: .medium, timeStyle: .none`), matching the card's own
/// "never editorializes with relative time" guardrail. The permalink is
/// intentionally NOT included in the text — it's carried as a separate
/// metadata field (`writePNG`) and share item, so it isn't duplicated here.
enum ShareCardAltText {
    /// Example shapes (from the design deck):
    /// - Post: `Lemmy post in c/linux@lemmy.ml: "TITLE", 3.4K points, 612
    ///   comments, Jul 12, 2026. Shared via Spud.`
    /// - Comment: `Comment by u/name@instance in c/…: "BODY-PREFIX…", 52
    ///   points, Jul 12, 2026. Shared via Spud.`
    static func make(content: ShareCardContent, options: ShareCardOptions) -> String {
        switch content.kind {
        case .post:
            postAltText(content: content)
        case .comment:
            commentAltText(content: content, options: options)
        }
    }

    private static func postAltText(content: ShareCardContent) -> String {
        guard let post = content.post else { return "" }
        let parts = [
            "\(CountFormatter.string(post.score)) points",
            "\(CountFormatter.string(post.commentCount)) comments",
            mediumDateString(post.published),
        ]
        return "Lemmy post in \(post.communityHandle): \"\(post.title)\", \(parts.joined(separator: ", ")). " +
            "Shared via Spud."
    }

    private static func commentAltText(content: ShareCardContent, options: ShareCardOptions) -> String {
        guard let destination = content.chain.last(where: \.isDestination) else { return "" }

        var subject = "Comment"
        if !options.redactIdentities, let authorHandle = destination.authorHandle {
            subject += " by \(authorHandle)"
        }
        if let communityHandle = content.post?.communityHandle {
            subject += " in \(communityHandle)"
        }

        var parts = ["\(CountFormatter.string(destination.score)) points"]
        if let published = destination.published {
            parts.append(mediumDateString(published))
        }

        let bodyPrefix = truncatedBodyPrefix(destination.bodyPlain)
        return "\(subject): \"\(bodyPrefix)\", \(parts.joined(separator: ", ")). Shared via Spud."
    }

    /// Caps a comment body preview so the alt text stays a short description
    /// rather than embedding the whole comment.
    private static func truncatedBodyPrefix(_ text: String?, limit: Int = 60) -> String {
        guard let text, !text.isEmpty else { return "" }
        guard text.count > limit else { return text }
        return "\(text.prefix(limit))\u{2026}"
    }

    private static func mediumDateString(_ date: Date) -> String {
        // Built locally per call, never a `static let` - see CLAUDE.md's
        // note on non-Sendable formatters in non-`@MainActor` types.
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
