//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// A single stat tile shown in the Summary dashboard.
///
/// `key` is a stable identifier used for equating tiles; `label` is the
/// user-visible tile heading; `value` is the formatted count string; `icon` is
/// an SF Symbol name; `source` describes data provenance; `note` is an
/// optional sub-label (e.g. "new" for forward-only tallies).
public struct SummaryStat: Sendable, Equatable {
    // MARK: Nested types

    /// Describes where a stat value comes from.
    public enum Source: Sendable, Equatable {
        /// Pulled from the Lemmy server (e.g. post/comment karma).
        case server
        /// Derived from local-only interaction logs (e.g. reads, saves).
        case local
        /// A forward-only log accumulated on-device; not backfilled from the server.
        case forward
    }

    // MARK: Properties

    public let key: String
    public let label: String
    public let value: String
    public let icon: String
    public let source: Source
    /// Optional sub-label displayed beneath the value (e.g. "new").
    public let note: String?

    // MARK: Init

    public init(
        key: String,
        label: String,
        value: String,
        icon: String,
        source: Source,
        note: String? = nil
    ) {
        self.key = key
        self.label = label
        self.value = value
        self.icon = icon
        self.source = source
        self.note = note
    }
}

/// Aggregated stats snapshot for one account's Summary dashboard.
///
/// `tiles` is ordered: Posts, Comments, Saved, Votes cast, Communities,
/// Posts read.  `name`, `joined`, and `cakeDay` are the identity fields shown
/// at the top of the dashboard.
public struct SummaryStats: Sendable, Equatable {
    // MARK: Properties

    /// Exactly six stat tiles in the prescribed display order.
    public let tiles: [SummaryStat]
    /// The account holder's display name (falls back to handle).
    public let name: String
    /// Relative joined string (e.g. "3 years ago").
    public let joined: String
    /// Absolute account creation date (e.g. "May 6, 2023").
    public let cakeDay: String

    // MARK: Init

    public init(tiles: [SummaryStat], name: String, joined: String, cakeDay: String) {
        self.tiles = tiles
        self.name = name
        self.joined = joined
        self.cakeDay = cakeDay
    }
}
