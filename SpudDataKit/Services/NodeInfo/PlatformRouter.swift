//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Why a home connection is being evaluated. Some software Spud can drive for
/// signing in (PieFed via its Lemmy-compatible dialect) still can't be used to
/// create a NEW account in-app, so the decision depends on the intent.
public enum HomeConnectionPurpose: Sendable {
    /// Signing in to (or re-authenticating) an existing account, or browsing
    /// signed-out.
    case login
    /// Creating a brand-new account from inside the app.
    case register
}

/// Decides whether a host may become a Spud home connection, based on its
/// detected software and the purpose of the connection. Software Spud can't
/// drive blocks; software that can be driven but has no in-app registration
/// blocks only `.register`; could-not-detect never blocks.
public struct PlatformRouter: Sendable {
    public enum HomeConnectionDecision: Sendable, Equatable {
        case allow
        case block(software: InstanceSoftware, displayName: String, version: String?)
    }

    private let nodeInfoService: NodeInfoServiceType

    public init(nodeInfoService: NodeInfoServiceType) {
        self.nodeInfoService = nodeInfoService
    }

    public func evaluateHomeConnection(host: String, purpose: HomeConnectionPurpose) async -> HomeConnectionDecision {
        switch await nodeInfoService.detect(host: host) {
        case let .known(software, version):
            let profile = PlatformProfile.profile(for: software, version: version)
            // Block if Spud can't drive this software at all, or if the caller
            // wants to register on software whose sign-up is not available in-app
            // (e.g. PieFed, which Spud CAN log in to but not create accounts on).
            let blocked = !profile.canBeHomeConnection
                || (purpose == .register && !profile.supportsAppRegistration)
            return blocked
                ? .block(software: software, displayName: profile.displayName, version: version)
                : .allow
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
