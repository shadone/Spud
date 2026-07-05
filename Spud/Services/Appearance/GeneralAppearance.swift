//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUIKit
import UIKit

class GeneralAppearance {
    let upvoteIcon = UIImage(systemName: "arrow.up")!
    let downvoteIcon = UIImage(systemName: "arrow.down")!

    /// The design's "down" token (#5b57e0): the downvoted state and negative
    /// scores. A fixed indigo, distinct from the accent (which drives the
    /// upvoted state). Computed so it stays concurrency-safe (UIColor isn't
    /// `Sendable`, so it can't be a shared `static let`).
    static var downColor: UIColor {
        UIColor(red: 0.357, green: 0.341, blue: 0.878, alpha: 1)
    }

    /// Upvote follows the user's accent (the design tints every upvote with the
    /// accent); downvote uses the fixed "down" token. Both resolve live so a
    /// change of accent is reflected without rebuilding the appearance.
    var upvoteButtonActiveColor: UIColor {
        ThemeManager.currentAccentColor
    }

    var downvoteButtonActiveColor: UIColor {
        Self.downColor
    }

    var upvoteSwipeActionBackgroundColor: UIColor {
        ThemeManager.currentAccentColor
    }

    var downvoteSwipeActionBackgroundColor: UIColor {
        Self.downColor
    }
}
