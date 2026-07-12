//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

/// A feature Spud needs the home instance's API to support. Semantic — UI and
/// services ask "can this instance do X?", never "which Lemmy version is it?",
/// so the version->capability table stays in exactly one place (below).
public enum InstanceCapability: String, Sendable, CaseIterable, Codable {
    case personProfiles
    case inbox
    case privateMessages
    case imageUpload
    case serverUserSettings
    case hidePosts
    /// Server-side read-state sync (`/post/mark_as_read`). Never surfaces UI:
    /// read tracking is locally owned (postInteraction), so the service just
    /// skips the server push when unavailable.
    case markPostsRead
}

/// The set of `InstanceCapability` an instance supports, derived from its
/// software + version. Fail-open: anything not positively known to be
/// unavailable is available (mirrors NodeInfo detection's fail-open rule —
/// a mis-gate is worse than a raw server error).
public struct InstanceCapabilities: Sendable, Equatable {
    private let unavailable: Set<InstanceCapability>

    /// Builds a capability set that withholds exactly `unavailable`; every other
    /// capability reads as available (fail-open). Pass `[]` (or use
    /// ``allAvailable``) for "everything supported". Exposed so a caller — or a
    /// test — can construct a specific gated set directly, independent of the
    /// version-derivation table below, which today gates nothing (see
    /// ``capabilities(software:version:)``).
    public init(unavailable: Set<InstanceCapability>) {
        self.unavailable = unavailable
    }

    public func can(_ capability: InstanceCapability) -> Bool {
        !unavailable.contains(capability)
    }

    public static let allAvailable = InstanceCapabilities(unavailable: [])

    /// The version-derivation table. **Gates nothing today**: it returns
    /// ``allAvailable`` for every input.
    ///
    /// Spud speaks both Lemmy's stable v3 API (pre-1.0 instances) and the native
    /// v4 API (the 1.0 rewrite — initiative Phase 6), so all seven capabilities
    /// — person profiles, inbox, private messages, image upload, server
    /// settings, hide-posts, and mark-posts-read — work on every Lemmy version.
    /// The Phase-1 gating that briefly withheld these on Lemmy 1.0, back when
    /// Spud spoke only v3 and the 1.0 server's v3 compat shim lacked the
    /// endpoints, has been retired now that Spud speaks v4 natively.
    ///
    /// The gating MECHANISM is deliberately kept intact — this function, the
    /// service-level ``LemmyServiceError/unsupportedByInstance`` backstop, and
    /// the UI gates all remain — so a future capability whose support genuinely
    /// varies by software or version can be re-added to a real gated set here
    /// without re-plumbing anything. Non-Lemmy software also fails open: it
    /// cannot be a home connection at all (`PlatformRouter` blocks it), and its
    /// version numbers must not be read on the Lemmy scale.
    public static func capabilities(
        software _: InstanceSoftware,
        version _: LemmyVersion?
    ) -> InstanceCapabilities {
        .allAvailable
    }
}
