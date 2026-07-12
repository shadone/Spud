//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Builds the composer body used to seed a cross-post, mirroring lemmy-ui's
/// `crossPostBody` (`post-listing.tsx`).
///
/// When the original post has a body, the result attributes the new post back
/// to it via Lemmy's `cross_posted_from` convention (`"cross-posted from: "` —
/// the literal English string, matched byte-for-byte so it federates the same
/// way other Lemmy clients' cross-posts do), followed by the original's ap_id
/// and the body quoted line-by-line. Spud's markdown autolinker already turns
/// a bare URL into a link and `LemmyURLParser.classify` resolves a Lemmy post
/// permalink to an in-app one, so the ap_id becomes a tappable in-app link
/// with no special-case parsing needed here.
///
/// A link (or otherwise body-less) post has nothing to quote — its pre-filled
/// title + url alone establish the cross-post (Lemmy links posts by url), so
/// this returns nil and the composer body is left for the user to fill in.
///
/// - Parameters:
///   - originalApId: the original post's federation permalink (`post.ap_id`).
///   - originalBody: the original post's body, or nil/blank for a link post.
/// - Returns: the attribution body to seed the composer with, or nil when the
///   original has no (non-blank) body.
func crossPostBody(originalApId: String, originalBody: String?) -> String? {
    guard let originalBody else { return nil }
    guard !originalBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

    let quoted = originalBody
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { "> \($0)" }
        .joined(separator: "\n")

    return "cross-posted from: \(originalApId)\n\n\(quoted)"
}
