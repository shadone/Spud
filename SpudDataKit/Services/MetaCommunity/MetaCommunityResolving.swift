//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// A community resolved from a candidate name against an instance.
public struct ResolvedMetaCandidate: Sendable, Equatable {
    public let name: String
    public let title: String?
    public let actorId: String
    public let instanceHost: String

    public init(name: String, title: String?, actorId: String, instanceHost: String) {
        self.name = name
        self.title = title
        self.actorId = actorId
        self.instanceHost = instanceHost
    }
}

/// Narrow seam over "resolve one candidate community name on one instance".
/// The live implementation goes through `LemmyService.fetchCommunityInfo`;
/// tests inject a fake. Returns nil when the community does not exist there.
public protocol MetaCommunityResolving: Sendable {
    func resolveCandidate(
        name: String,
        onHost host: String,
        forAccountKeychainId keychainId: String
    ) async -> ResolvedMetaCandidate?
}

/// The fixed candidate names probed against each instance. Bounded so a refresh
/// is at most this many lookups. Broad enough for common meta communities;
/// oddly-named ones are still badged in lists via the inline classifier.
public enum MetaCommunityCandidates {
    public static let `default`: [String] = [
        "meta", "announcements", "support", "help", "feedback", "changelog",
        "news", "updates", "admin", "welcome", "rules", "site",
    ]
}
