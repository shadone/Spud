//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// Shared Liquid Glass constants for the app's own floating chrome.
///
/// These are tokens, not a wrapper: call sites build their own
/// `UIVisualEffectView` and apply glass through UIKit's API directly. The
/// tokens exist so the handful of bespoke glass surfaces agree on material and
/// spacing rather than each choosing their own.
///
/// Glass belongs to the navigation layer. Do not apply these to content — see
/// `NsfwBlurOverlayView`, which is deliberately a blur because a content
/// obscurer must not be see-through.
public enum GlassTokens {
    /// The material for floating controls layered over content.
    public static var controlSurface: UIGlassEffect {
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = true
        return effect
    }

    /// Distance at which sibling glass elements begin to merge, for a
    /// `UIGlassContainerEffect` grouping related controls.
    public static let controlContainerSpacing: CGFloat = 12
}
