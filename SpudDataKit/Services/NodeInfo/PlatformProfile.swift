//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

/// What Spud can do with an instance running a given `InstanceSoftware`.
/// Pure lookup, no I/O.
public struct PlatformProfile: Sendable, Equatable {
    public let software: InstanceSoftware
    public let version: String?
    /// Human-facing name for messages and badges.
    public let displayName: String
    /// Whether Spud's `LemmyService` can drive this software's API surface:
    /// Lemmy (v3/v4) natively, and PieFed via its Lemmy-compatible `/api/alpha`
    /// dialect. Everything else (Mbin, Mastodon, forks, ...) is not drivable.
    public let speaksLemmyAPI: Bool

    /// Whether this instance can be a Spud home connection (login / signed-out browse).
    public var canBeHomeConnection: Bool {
        speaksLemmyAPI
    }

    /// Whether Spud can create a NEW account against this software from inside
    /// the app. Only `.lemmy` exposes a machine-usable registration endpoint
    /// Spud drives: PieFed registration is web-only (verified 2026-07-15 — its
    /// `/api/alpha` write surface has no working sign-up flow), so a PieFed home
    /// connection is allowed for login but its in-app registration is routed to
    /// the browser instead. Non-Lemmy software that can't be a home connection
    /// at all is likewise `false` here.
    public var supportsAppRegistration: Bool {
        software == .lemmy
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
            speaksLemmyAPI: software == .lemmy || software == .piefed
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
