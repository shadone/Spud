//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

/// What Spud can do with an instance running a given `InstanceSoftware`.
/// Pure lookup, no I/O. In v1 only Lemmy speaks the API Spud uses.
public struct PlatformProfile: Sendable, Equatable {
    public let software: InstanceSoftware
    public let version: String?
    /// Human-facing name for messages and badges.
    public let displayName: String
    /// Whether Spud's LemmyService can talk to this software. v1: only `.lemmy`.
    public let speaksLemmyAPI: Bool

    /// Whether this instance can be a Spud home connection (login / signed-out browse).
    public var canBeHomeConnection: Bool {
        speaksLemmyAPI
    }

    /// What the instance's API supports, derived from software + version.
    /// See `InstanceCapabilities.capabilities(software:version:)` for the table.
    public var capabilities: InstanceCapabilities {
        InstanceCapabilities.capabilities(
            software: software,
            version: version.flatMap(LemmyVersion.init(parsing:))
        )
    }

    public static func profile(for software: InstanceSoftware, version: String? = nil) -> PlatformProfile {
        PlatformProfile(
            software: software,
            version: version,
            displayName: displayName(for: software),
            speaksLemmyAPI: software == .lemmy
        )
    }

    private static func displayName(for software: InstanceSoftware) -> String {
        switch software {
        case .lemmy: "Lemmy"
        case .piefed: "PieFed"
        case .mbin: "Mbin"
        case .kbin: "/kbin"
        case .mastodon: "Mastodon"
        case .misskey: "Misskey"
        case .pleroma: "Pleroma"
        case .peertube: "PeerTube"
        case .friendica: "Friendica"
        case .gotosocial: "GoToSocial"
        case let .other(name): name
        }
    }
}
