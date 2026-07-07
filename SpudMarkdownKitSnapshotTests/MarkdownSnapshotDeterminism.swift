//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// Local counterpart to `SpudSnapshotTests/SnapshotDeterminism.contentSizeTrait`.
///
/// This target depends only on `SpudMarkdownKit` (never `Spud`), so it cannot see
/// that type — `SnapshotDeterminism` is defined inside the `SpudSnapshotTests` test
/// target itself, not a shared framework. The pin is replicated here rather than
/// shared.
///
/// On 2026-07-06 the shared reference simulator's Dynamic Type setting was found
/// knocked to `.medium` (one notch below the `.large` default), surviving Mac
/// reboots. A snapshot's own `traits:` argument that never sets
/// `preferredContentSizeCategory` leaves that trait unspecified, so it falls
/// through to the render's ambient trait environment — the actual simulator's live
/// Dynamic Type setting — rather than anything the test declared. Every capture in
/// this target built its `traits:` from `userInterfaceStyle` alone, so all of them
/// were exposed to that drift. Pinning `preferredContentSizeCategory` explicitly
/// makes the render immune to the sim's persisted setting regardless of what it
/// drifts to next. See `SnapshotDeterminism.contentSizeTrait`'s doc comment for the
/// full incident writeup.
enum MarkdownSnapshotDeterminism {
    static let contentSizeTrait = UITraitCollection(preferredContentSizeCategory: .large)

    /// Builds this target's capture traits: the requested appearance plus the
    /// pinned content-size category.
    static func traits(_ style: UIUserInterfaceStyle) -> UITraitCollection {
        UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: style),
            contentSizeTrait,
        ])
    }
}
