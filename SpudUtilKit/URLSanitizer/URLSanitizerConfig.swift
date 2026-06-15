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
    public var frontEnds: [FrontEndConfig]

    public init(
        isEnabled: Bool,
        stripTrackingParams: Bool,
        unwrapRedirectors: Bool,
        upgradeToHTTPS: Bool,
        deAMP: Bool,
        redirectToFrontEnds: Bool,
        frontEnds: [FrontEndConfig]
    ) {
        self.isEnabled = isEnabled
        self.stripTrackingParams = stripTrackingParams
        self.unwrapRedirectors = unwrapRedirectors
        self.upgradeToHTTPS = upgradeToHTTPS
        self.deAMP = deAMP
        self.redirectToFrontEnds = redirectToFrontEnds
        self.frontEnds = frontEnds
    }

    /// Safe steps on, front-end redirects off, hosts seeded from the catalog.
    public static let `default` = URLSanitizerConfig(
        isEnabled: true,
        stripTrackingParams: true,
        unwrapRedirectors: true,
        upgradeToHTTPS: true,
        deAMP: true,
        redirectToFrontEnds: false,
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
