//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// Pure size-class layout decisions shared by the iPad-adaptive surfaces, kept
/// free of view state so they can be unit-tested without a running view
/// hierarchy.
enum AdaptiveLayout {
    /// Default maximum readable content width for centered iPad layouts.
    static let contentMaxWidth: CGFloat = 600
    /// Maximum width for full-width directory/list content on a wide canvas.
    static let directoryMaxWidth: CGFloat = 700

    /// The downsample target width for a wide banner image: the screen width,
    /// capped so an iPad does not fetch a needlessly huge bitmap.
    static func bannerDownsampleWidth(screenWidth: CGFloat, cap: CGFloat = contentMaxWidth) -> CGFloat {
        Swift.min(screenWidth, cap)
    }
}
