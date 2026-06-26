//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUtilKit

/// Translates a `spud-markdown://mention|community|object?…` URL (as produced by
/// `SpudMarkdownKit`'s `InlineAttributedStringBuilder`) into the app's internal
/// link URL (the same scheme decoded by `URL.spud`).
///
/// Returns `nil` for any URL that is not a `spud-markdown://` link, so the
/// caller can fall through to normal link handling.
enum MarkdownInternalLink {
    static func resolve(_ url: URL) -> URL? {
        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme == "spud-markdown"
        else {
            return nil
        }

        let name = components.queryItems?.first(where: { $0.name == "name" })?.value
        let instanceString = components.queryItems?.first(where: { $0.name == "instance" })?.value

        switch components.host {
        case "object":
            // A post/comment resolved by its federation URL.
            guard
                let urlString = components.queryItems?.first(where: { $0.name == "url" })?.value,
                let objectURL = URL(string: urlString)
            else {
                return nil
            }
            return URL.SpudInternalLink.objectAtURL(url: objectURL).url

        case "mention":
            guard
                let name,
                let instanceString,
                let userURL = URL(string: "https://\(instanceString)/u/\(name)")
            else {
                return nil
            }
            return URL.SpudInternalLink.objectAtURL(url: userURL).url

        case "community":
            guard
                let name,
                let instanceString,
                let instance = InstanceActorId(from: "https://\(instanceString)")
            else {
                return nil
            }
            return URL.SpudInternalLink.community(name: name, instance: instance).url

        default:
            return nil
        }
    }
}
