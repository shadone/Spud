//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Per-service front-end redirect setting.
public struct FrontEndConfig: Codable, Equatable, Sendable {
    public let service: FrontEndService
    public var isEnabled: Bool
    public var host: String

    public init(service: FrontEndService, isEnabled: Bool, host: String) {
        self.service = service
        self.isEnabled = isEnabled
        self.host = host
    }
}

/// User configuration for the outbound URL hygiene pipeline. Stored as JSON in
/// UserDefaults via `@UserDefaultsBacked`.
public struct URLSanitizerConfig: Codable, Equatable, Sendable {
    /// Master switch. When false, ``URLSanitizer`` returns URLs unchanged.
    public var isEnabled: Bool
    public var stripTrackingParams: Bool
    public var unwrapRedirectors: Bool
    public var upgradeToHTTPS: Bool
    public var deAMP: Bool
    /// Category master for front-end redirects. Individual services are gated
    /// by their own ``FrontEndConfig/isEnabled`` in ``frontEnds``.
    public var redirectToFrontEnds: Bool
    /// When true, links already on a third-party front-end (Invidious/Piped) are
    /// also normalized to the chosen YouTube front-end host — e.g. open Invidious
    /// links in Piped. Subordinate to ``redirectToFrontEnds`` and the youtube
    /// service being enabled. Canonical youtube.com/youtu.be rewriting ignores
    /// this flag.
    public var rewriteThirdPartyFrontEnds: Bool
    /// Opt-in: resolve YouTube-family video posts' inline stream through the
    /// default cataloged Piped instance when the user's YouTube front-end is
    /// not Piped. A configured Piped front-end still takes precedence. Playback
    /// traffic goes to Piped, never Google. Independent of ``isEnabled`` — the
    /// master switch gates link rewriting, not playback resolution.
    public var inlinePlaybackViaPiped: Bool
    public var frontEnds: [FrontEndConfig]

    public init(
        isEnabled: Bool,
        stripTrackingParams: Bool,
        unwrapRedirectors: Bool,
        upgradeToHTTPS: Bool,
        deAMP: Bool,
        redirectToFrontEnds: Bool,
        rewriteThirdPartyFrontEnds: Bool,
        inlinePlaybackViaPiped: Bool = false,
        frontEnds: [FrontEndConfig]
    ) {
        self.isEnabled = isEnabled
        self.stripTrackingParams = stripTrackingParams
        self.unwrapRedirectors = unwrapRedirectors
        self.upgradeToHTTPS = upgradeToHTTPS
        self.deAMP = deAMP
        self.redirectToFrontEnds = redirectToFrontEnds
        self.rewriteThirdPartyFrontEnds = rewriteThirdPartyFrontEnds
        self.inlinePlaybackViaPiped = inlinePlaybackViaPiped
        self.frontEnds = frontEnds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        stripTrackingParams = try container.decode(Bool.self, forKey: .stripTrackingParams)
        unwrapRedirectors = try container.decode(Bool.self, forKey: .unwrapRedirectors)
        upgradeToHTTPS = try container.decode(Bool.self, forKey: .upgradeToHTTPS)
        deAMP = try container.decode(Bool.self, forKey: .deAMP)
        redirectToFrontEnds = try container.decode(Bool.self, forKey: .redirectToFrontEnds)
        frontEnds = try container.decode([FrontEndConfig].self, forKey: .frontEnds)
        // New in 2026-07: absent in configs written by older builds.
        rewriteThirdPartyFrontEnds = try container.decodeIfPresent(Bool.self, forKey: .rewriteThirdPartyFrontEnds) ?? false
        // New in 2026-07: absent in configs written by older builds.
        inlinePlaybackViaPiped = try container.decodeIfPresent(Bool.self, forKey: .inlinePlaybackViaPiped) ?? false
    }

    /// Safe steps on, front-end redirects off, hosts seeded from the catalog.
    public static let `default` = URLSanitizerConfig(
        isEnabled: true,
        stripTrackingParams: true,
        unwrapRedirectors: true,
        upgradeToHTTPS: true,
        deAMP: true,
        redirectToFrontEnds: false,
        rewriteThirdPartyFrontEnds: false,
        inlinePlaybackViaPiped: false,
        frontEnds: FrontEndCatalog.entries.map {
            FrontEndConfig(service: $0.service, isEnabled: false, host: $0.defaultHost)
        }
    )

    /// The stored setting for `service`, falling back to a disabled
    /// catalog-default entry when the stored config predates the service.
    public func setting(for service: FrontEndService) -> FrontEndConfig {
        frontEnds.first { $0.service == service }
            ?? FrontEndConfig(
                service: service,
                isEnabled: false,
                host: FrontEndCatalog.entry(for: service).defaultHost
            )
    }
}
