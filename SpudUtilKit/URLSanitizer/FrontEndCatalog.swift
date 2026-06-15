//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Built-in definitions for each ``FrontEndService``: the source domains it
/// matches and the default privacy front-end host. Hosts are examples that
/// rot over time, so the user can override them in settings.
public enum FrontEndCatalog {
    public struct Entry: Sendable {
        public let service: FrontEndService
        public let displayName: String
        /// Base hosts (lowercased, no `www.`/`m.`/`mobile.` prefix) that map to this service.
        public let sourceDomains: [String]
        public let defaultHost: String
    }

    public static let entries: [Entry] = FrontEndService.allCases.map { entry(for: $0) }

    public static func entry(for service: FrontEndService) -> Entry {
        switch service {
        case .twitter:
            Entry(service: .twitter, displayName: "X / Twitter", sourceDomains: ["twitter.com", "x.com"], defaultHost: "xcancel.com")
        case .youtube:
            Entry(service: .youtube, displayName: "YouTube", sourceDomains: ["youtube.com", "youtu.be"], defaultHost: "yewtu.be")
        case .reddit:
            Entry(service: .reddit, displayName: "Reddit", sourceDomains: ["reddit.com"], defaultHost: "redlib.catsarch.com")
        case .imgur:
            Entry(service: .imgur, displayName: "Imgur", sourceDomains: ["imgur.com"], defaultHost: "rimgo.app")
        }
    }
}
