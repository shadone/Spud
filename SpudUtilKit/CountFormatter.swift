//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// The single compact-count formatter for the whole app (app, data layer, and
/// widget). Renders "312", "1.2K", "32K", "1.2M": K/M suffixes, dropping the
/// decimal for whole values or when the abbreviated value is >= 100. Values
/// below 1000 and all negatives render verbatim.
public enum CountFormatter {
    public static func string(_ value: Int64) -> String {
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
