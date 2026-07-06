//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Decides whether a host may become a Spud home connection, based on its
/// detected software. Detected-non-Lemmy blocks; could-not-detect never blocks.
public struct PlatformRouter: Sendable {
    public enum HomeConnectionDecision: Sendable, Equatable {
        case allow
        case block(software: InstanceSoftware, displayName: String, version: String?)
    }

    private let nodeInfoService: NodeInfoServiceType

    public init(nodeInfoService: NodeInfoServiceType) {
        self.nodeInfoService = nodeInfoService
    }

    public func evaluateHomeConnection(host: String) async -> HomeConnectionDecision {
        switch await nodeInfoService.detect(host: host) {
        case let .known(software, version):
            let profile = PlatformProfile.profile(for: software, version: version)
            return profile.canBeHomeConnection
                ? .allow
                : .block(software: software, displayName: profile.displayName, version: version)
        case .unknown:
            // Fail-open: a WAF-403'd healthy Lemmy instance must still work.
            return .allow
        }
    }
}

/// Thrown by `AccountService` when a home connection targets non-Lemmy software.
public struct PlatformUnsupportedError: Error, Equatable, Sendable {
    public let software: InstanceSoftware
    public let displayName: String
    public let version: String?
    public let host: String

    public init(software: InstanceSoftware, displayName: String, version: String?, host: String) {
        self.software = software
        self.displayName = displayName
        self.version = version
        self.host = host
    }
}
