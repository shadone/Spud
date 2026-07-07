//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

/// A parsed Lemmy server version ("0.19.11", "1.0.0-alpha.18"). Only the
/// numeric major.minor.patch core is modelled; prerelease identifiers are
/// tolerated and discarded (an alpha of 1.0 gates like 1.0). Parsing is
/// strict about the leading component: a string whose first dot-separated
/// component is not a plain integer is unparseable (nil), so arbitrary fork
/// version strings fail open rather than mis-gate.
public struct LemmyVersion: Sendable, Equatable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init?(parsing string: String) {
        // Strip a prerelease/build suffix: "1.0.0-alpha.18" -> "1.0.0".
        // omittingEmptySubsequences: false is load-bearing twice over: it
        // guarantees a non-empty array (so [0] can't trap on ""), and it keeps
        // a leading "-" ("-1.0.0") as an empty core that fails the major-int
        // guard below instead of silently parsing the suffix as a version.
        let core = string.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let parts = core.split(separator: ".")
        guard let first = parts.first, let major = Int(first) else { return nil }
        self.major = major
        minor = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        patch = parts.count > 2 ? Int(parts[2]) ?? 0 : 0
    }
}
