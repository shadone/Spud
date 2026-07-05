//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Compact count formatting shared by instance-health chips and onboarding
/// member counts, e.g. "312", "1.2K", "32K", "1.2M".
///
/// Deliberately NOT unified with `CommentsFormatter` (K-only style) or the
/// Activity heatmap's formatter — their output styles differ and are pinned
/// by snapshot references; see docs/superpowers/specs/2026-07-05-follow-ups.md.
enum CompactCount {
    static func string(_ value: Int64) -> String {
        let n = Double(value)
        switch value {
        case 1_000_000...: return trim(n / 1_000_000) + "M"
        case 1000...: return trim(n / 1000) + "K"
        default: return "\(value)"
        }
    }

    private static func trim(_ value: Double) -> String {
        if value >= 100 || value == value.rounded() {
            return "\(Int(value.rounded()))"
        }
        return String(format: "%.1f", value)
    }
}
