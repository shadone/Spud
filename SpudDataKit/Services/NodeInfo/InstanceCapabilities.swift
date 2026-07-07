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

    public func can(_ capability: InstanceCapability) -> Bool {
        !unavailable.contains(capability)
    }

    public static let allAvailable = InstanceCapabilities(unavailable: [])

    /// The derivation table. Lemmy >= 1.0 is reached through its partial v3
    /// compat shim until Spud speaks the v4 API (initiative Phase 5/6); the
    /// shim lacks exactly these endpoints: person details, replies/mentions,
    /// all private-message operations, image upload, `/post/hide`,
    /// `/post/mark_as_read`, and `save_user_settings`. Non-Lemmy software
    /// fails open — it cannot be a home connection at all (`PlatformRouter`),
    /// and its version numbers must not be read on the Lemmy scale.
    public static func capabilities(
        software: InstanceSoftware,
        version: LemmyVersion?
    ) -> InstanceCapabilities {
        guard software == .lemmy, let version, version.major >= 1 else {
            return .allAvailable
        }
        // Listed explicitly (not allCases) so adding a capability to the enum
        // forces a deliberate row here instead of inheriting gating silently.
        return InstanceCapabilities(unavailable: [
            .personProfiles,
            .inbox,
            .privateMessages,
            .imageUpload,
            .serverUserSettings,
            .hidePosts,
            .markPostsRead,
        ])
    }
}
