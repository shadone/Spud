//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// A curated bundle of communities a new user can follow together to fill a
/// quiet feed fast. The curation (which communities, in what order) is fixed;
/// the live stats (members, activity, icons) are resolved from the Explorer
/// directory at render time, so the numbers never go stale.
public struct StarterPack: Sendable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let blurb: String
    /// Community actor ids, e.g. "https://lemmy.world/c/technology".
    public let communityUrls: [String]

    public init(id: String, title: String, blurb: String, communityUrls: [String]) {
        self.id = id
        self.title = title
        self.blurb = blurb
        self.communityUrls = communityUrls
    }
}

/// A ``StarterPack`` with its member communities resolved against the live
/// directory.
public struct ResolvedStarterPack: Sendable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let blurb: String
    public let communities: [CommunityListRow]

    public var communityCount: Int {
        communities.count
    }

    public var totalSubscribers: Int64 {
        communities.reduce(0) { $0 + $1.numberOfSubscribers }
    }
}

/// The curated starter-pack catalog. Embedded in code for now (a bundled JSON
/// resource can replace `all` later without changing the resolver or the UI).
public enum StarterPackCatalog {
    public static let all: [StarterPack] = [
        StarterPack(
            id: "tech",
            title: "Tech Essentials",
            blurb: "The core technology, programming and self-hosting hubs.",
            communityUrls: [
                "https://lemmy.world/c/technology",
                "https://programming.dev/c/programming",
                "https://lemmy.world/c/selfhosted",
                "https://lemmy.ml/c/linux",
                "https://lemmy.ml/c/privacy",
                "https://lemmy.ml/c/opensource",
            ]
        ),
        StarterPack(
            id: "fresh",
            title: "Fresh to Lemmy",
            blurb: "A friendly cross-section to fill a quiet feed fast.",
            communityUrls: [
                "https://lemmy.ml/c/asklemmy",
                "https://lemmy.world/c/technology",
                "https://lemmy.ml/c/worldnews",
                "https://lemmy.world/c/memes",
                "https://lemmy.world/c/news",
                "https://lemmy.world/c/movies",
            ]
        ),
        StarterPack(
            id: "gaming",
            title: "Gaming Starter",
            blurb: "Big gaming hubs plus a couple of cozy corners.",
            communityUrls: [
                "https://lemmy.world/c/gaming",
                "https://lemmy.world/c/games",
                "https://lemmy.ml/c/gaming",
                "https://lemmy.world/c/patientgamers",
                "https://lemmy.world/c/pcgaming",
            ]
        ),
        StarterPack(
            id: "news",
            title: "News & World",
            blurb: "Wire services, regional desks and analysis.",
            communityUrls: [
                "https://lemmy.ml/c/worldnews",
                "https://lemmy.world/c/news",
                "https://lemmy.world/c/worldnews",
                "https://beehaw.org/c/news",
            ]
        ),
        StarterPack(
            id: "science",
            title: "Science & Space",
            blurb: "Research, the natural world and the cosmos.",
            communityUrls: [
                "https://lemmy.world/c/science",
                "https://beehaw.org/c/science",
                "https://lemmy.world/c/space",
                "https://mander.xyz/c/astronomy",
            ]
        ),
        StarterPack(
            id: "creative",
            title: "Creative",
            blurb: "Photography, design, music and the arts.",
            communityUrls: [
                "https://lemmy.world/c/photography",
                "https://lemmy.ml/c/art",
                "https://lemmy.world/c/music",
                "https://lemmy.world/c/design",
            ]
        ),
    ]

    /// Resolve `packs` against directory `rows`, attaching each pack's live
    /// communities (matched by actor id, in the curated order). Packs whose
    /// communities are all missing from the directory are dropped.
    public static func resolve(
        _ packs: [StarterPack] = all,
        using rows: [CommunityListRow]
    ) -> [ResolvedStarterPack] {
        let byUrl = Dictionary(rows.map { ($0.communityUrl, $0) }, uniquingKeysWith: { first, _ in first })
        return packs.compactMap { pack in
            let communities = pack.communityUrls.compactMap { byUrl[$0] }
            guard !communities.isEmpty else { return nil }
            return ResolvedStarterPack(
                id: pack.id,
                title: pack.title,
                blurb: pack.blurb,
                communities: communities
            )
        }
    }
}
