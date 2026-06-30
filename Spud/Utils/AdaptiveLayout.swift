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

    /// Clamps an available width to a maximum so content does not stretch
    /// full-bleed on a wide (iPad) canvas.
    static func cappedContentWidth(available: CGFloat, max: CGFloat) -> CGFloat {
        Swift.min(available, max)
    }

    /// The downsample target width for a wide banner image: the screen width,
    /// capped so an iPad does not fetch a needlessly huge bitmap.
    static func bannerDownsampleWidth(screenWidth: CGFloat, cap: CGFloat = contentMaxWidth) -> CGFloat {
        Swift.min(screenWidth, cap)
    }

    /// Modal presentation style for a row-anchored chooser: a popover in the
    /// regular size class (iPad), a draggable bottom sheet in compact (iPhone).
    static func modalPresentationStyle(for sizeClass: UIUserInterfaceSizeClass) -> UIModalPresentationStyle {
        sizeClass == .regular ? .popover : .pageSheet
    }
}
