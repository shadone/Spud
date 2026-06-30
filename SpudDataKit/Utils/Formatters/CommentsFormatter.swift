//
// Copyright (c) 2021-2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Formats numeric counts (posts, comments, subscribers, etc.) into compact
/// display strings. Numbers below 1 000 are rendered verbatim; thousands are
/// abbreviated with a "K" suffix to one decimal place (e.g. 1 234 → "1.2K").
public enum CommentsFormatter {
    public static func string(from numberOfComments: Int64) -> String {
        if numberOfComments < 1000 {
            return String(numberOfComments)
        }
        return String(format: "%.1fK", Double(numberOfComments) / 1000)
    }
}
