//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUtilKit

/// Classifies Lemmy links found in body text into `URL.SpudInternalLink`.
///
/// Pure and side-effect free. The caller supplies `isKnownInstance` (backed by
/// the Explorer instance directory) so the parser stays free of database and
/// UIKit dependencies and is trivially testable.
///
/// Path-based content links (`/post`, `/c`, `/u`) are only recognised when the
/// host is a known instance, so a non-Lemmy `example.com/post/1` is left as a
/// plain external link. Mention shorthands (`!c@i`, `@u@i`) are unambiguous
/// Lemmy syntax and need no allowlist — the instance is named inline.
/// Comments (`/comment/N`) classify to `.objectAtURL` so the app resolves the
/// comment server-side (its local id is not known until resolved).
enum LemmyURLParser {
    static func classify(url: URL, isKnownInstance: (String) -> Bool) -> URL.SpudInternalLink? {
        guard
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            let host = url.host?.lowercased()
        else {
            return nil
        }

        let parts = url.path.split(separator: "/").map(String.init)

        // Bare instance root (no meaningful path segment).
        if parts.isEmpty {
            guard isKnownInstance(host), let instance = InstanceActorId(from: url) else {
                return nil
            }
            return .instance(instance: instance)
        }

        // Content paths are only trusted on known instances.
        guard isKnownInstance(host) else { return nil }

        // Frontend post URL (`/c/<community>/p/<id>[/<slug>]`) → resolve the
        // canonical post server-side.
        if let canonical = frontendPostURL(for: url) {
            return .objectAtURL(url: canonical)
        }

        switch (parts.first, parts.count) {
        case ("post", 2):
            guard Int32(parts[1]) != nil else { return nil }
            return .objectAtURL(url: url)

        case ("u", 2):
            return .objectAtURL(url: url)

        case ("c", 2):
            let (name, instance) = community(from: parts[1], linkHost: host, linkPort: url.port)
            return .community(name: name, instance: instance)

        case ("comment", 2):
            guard Int32(parts[1]) != nil else { return nil }
            return .objectAtURL(url: url)

        default:
            return nil
        }
    }

    /// Some Lemmy frontends (e.g. feddit.online) render a post at
    /// `/c/<community>/p/<id>[/<slug>]` instead of the canonical `/post/<id>`.
    /// Returns the canonical `https://<host>/post/<id>` URL for such a path (so the
    /// app resolves it server-side), or nil if the path isn't that shape.
    static func frontendPostURL(for url: URL) -> URL? {
        guard let host = url.host?.lowercased() else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 4, parts[0] == "c", parts[2] == "p", Int32(parts[3]) != nil else { return nil }
        let hostPort = url.port.map { "\(host):\($0)" } ?? host
        return URL(string: "https://\(hostPort)/post/\(parts[3])")
    }

    /// Splits a `/c/` segment into (name, home instance). A bare `name` is homed
    /// at the link's host; `name@otherhost` is homed at `otherhost`.
    private static func community(
        from segment: String,
        linkHost: String,
        linkPort: Int?
    ) -> (name: String, instance: InstanceActorId) {
        if let at = segment.firstIndex(of: "@") {
            let name = String(segment[segment.startIndex..<at])
            let host = String(segment[segment.index(after: at)...])
            return (name, InstanceActorId(from: "https://\(host)") ?? InstanceActorId.invalid)
        }
        // Build the link host URL to extract an InstanceActorId, preserving any non-standard port.
        let hostString: String
        if let port = linkPort {
            hostString = "https://\(linkHost):\(port)"
        } else {
            hostString = "https://\(linkHost)"
        }
        return (segment, InstanceActorId(from: hostString) ?? InstanceActorId.invalid)
    }

    // MARK: - Mentions

    struct Mention {
        let range: NSRange
        let link: URL.SpudInternalLink
    }

    // Compiled once; patterns are compile-time constants so `try!` cannot fail.
    // `mentions(in:)` runs on every body render, so recompiling per call would
    // be wasted work. The lookbehind excludes `!` too (symmetric with the user
    // pattern excluding `@`) so `!!c@host` does not match.
    private static let communityMentionRegex = try! NSRegularExpression(
        pattern: #"(?<![\w@./!])!([a-zA-Z0-9_]+)@([a-zA-Z0-9.-]+\.[a-zA-Z]{2,})"#
    )
    private static let userMentionRegex = try! NSRegularExpression(
        pattern: #"(?<![\w@./])@([a-zA-Z0-9_]+)@([a-zA-Z0-9.-]+\.[a-zA-Z]{2,})"#
    )

    /// Finds `!community@instance` and `@user@instance` mentions in `text`,
    /// returned in order of appearance. Communities map to `.community`; users
    /// map to `.objectAtURL` of the canonical `/u/` URL (resolved for the local
    /// person id at tap time).
    static func mentions(in text: String) -> [Mention] {
        var result: [Mention] = []
        result.append(contentsOf: matches(communityMentionRegex, in: text) { name, host in
            guard let instance = InstanceActorId(from: "https://\(host)") else { return nil }
            return .community(name: name, instance: instance)
        })
        result.append(contentsOf: matches(userMentionRegex, in: text) { name, host in
            guard let url = URL(string: "https://\(host)/u/\(name)") else { return nil }
            return .objectAtURL(url: url)
        })
        return result.sorted { $0.range.location < $1.range.location }
    }

    private static func matches(
        _ regex: NSRegularExpression,
        in text: String,
        make: (_ name: String, _ host: String) -> URL.SpudInternalLink?
    ) -> [Mention] {
        let full = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: full).compactMap { match in
            guard
                match.numberOfRanges == 3,
                let nameRange = Range(match.range(at: 1), in: text),
                let hostRange = Range(match.range(at: 2), in: text)
            else { return nil }
            guard let link = make(String(text[nameRange]), String(text[hostRange])) else { return nil }
            return Mention(range: match.range, link: link)
        }
    }
}
