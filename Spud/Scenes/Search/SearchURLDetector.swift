//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUtilKit

/// A Lemmy URL detected in the search field, ready to render as an "Open in
/// Spud" row and to route on tap.
struct SearchURLSuggestion {
    enum Kind: Hashable {
        case post, comment, community, user, instance
    }

    let kind: Kind
    let link: URL.SpudInternalLink
    let displayURL: String
}

/// Detects whether a search query is a Lemmy URL and produces a routable
/// suggestion. Pure and side-effect free; the caller supplies `isKnownInstance`
/// (Explorer directory lookup), mirroring `LemmyURLParser`.
///
/// Known-instance URLs and mentions go through `LemmyURLParser.classify`. As a
/// fallback, Lemmy-shaped paths on UNKNOWN hosts (`/post/<id>`, `/comment/<id>`,
/// `/c/<name>`, `/u/<name>`, and the frontend post form `/c/<community>/p/<id>`)
/// are still offered — the path is a strong Lemmy signal — and resolved federally
/// on tap via `.objectAtURL`. A bare host with no Lemmy-shaped path on an unknown
/// instance is not offered (it cannot be identified as Lemmy).
enum SearchURLDetector {
    static func detect(query: String, isKnownInstance: (String) -> Bool) -> SearchURLSuggestion? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let url = URL(string: trimmed),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            url.host != nil
        else {
            return nil
        }

        // Known instances + mentions: reuse the canonical classifier.
        if let link = LemmyURLParser.classify(url: url, isKnownInstance: isKnownInstance) {
            return SearchURLSuggestion(
                kind: kind(forKnownLink: link, path: url.path),
                link: link,
                displayURL: displayString(url)
            )
        }

        // Unknown-host fallback: trust Lemmy-shaped paths, resolve federally.
        // Frontend post URLs (`/c/<community>/p/<id>[/<slug>]`) first, since they
        // have more than two path segments.
        if let canonical = LemmyURLParser.frontendPostURL(for: url) {
            return SearchURLSuggestion(kind: .post, link: .objectAtURL(url: canonical), displayURL: displayString(url))
        }

        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count == 2 else { return nil }
        let kind: SearchURLSuggestion.Kind
        switch parts[0] {
        case "post":
            guard Int32(parts[1]) != nil else { return nil }
            kind = .post
        case "comment":
            guard Int32(parts[1]) != nil else { return nil }
            kind = .comment
        case "u":
            kind = .user
        case "c":
            kind = .community
        default:
            return nil
        }
        return SearchURLSuggestion(kind: kind, link: .objectAtURL(url: url), displayURL: displayString(url))
    }

    /// classify maps post/user/comment on known instances to `.objectAtURL`;
    /// recover the precise kind from the path so the row label is accurate.
    private static func kind(
        forKnownLink link: URL.SpudInternalLink,
        path: String
    ) -> SearchURLSuggestion.Kind {
        switch link {
        case .post: return .post
        case .person: return .user
        case .community: return .community
        case .instance: return .instance
        case .objectAtURL:
            let parts = path.split(separator: "/").map(String.init)
            switch parts.first {
            case "post": return .post
            case "comment": return .comment
            case "u": return .user
            default: return .post
            }
        }
    }

    /// Host + path with the scheme dropped, for a compact secondary label.
    private static func displayString(_ url: URL) -> String {
        let host = url.host ?? ""
        return url.path.isEmpty ? host : host + url.path
    }
}
