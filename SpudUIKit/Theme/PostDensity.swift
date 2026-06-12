//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// How tightly post-list cells are laid out.
///
/// `.comfortable` reproduces the pre-M8 look (generous 16pt cell margins,
/// 8pt stack spacing). `.compact` tightens the margins and spacing and trims
/// the font a touch, fitting more posts on screen — Apollo's "compact" feel.
public enum PostDensity: String, CaseIterable, Codable, Sendable, Identifiable {
    case comfortable
    case compact

    public var id: String {
        rawValue
    }

    /// Human-readable name for the settings picker.
    public var title: String {
        switch self {
        case .comfortable:
            return "Comfortable"
        case .compact:
            return "Compact"
        }
    }

    /// SF Symbol representing this density in the settings picker.
    public var symbolName: String {
        switch self {
        case .comfortable:
            return "rectangle.grid.1x2"
        case .compact:
            return "rectangle.grid.1x2.fill"
        }
    }

    // MARK: Layout metrics consumed by the post-list cell

    /// The cell's content inset from the table edges.
    public var cellMargin: CGFloat {
        switch self {
        case .comfortable:
            return 16
        case .compact:
            return 10
        }
    }

    /// Spacing between the thumbnail and the text column.
    public var horizontalSpacing: CGFloat {
        switch self {
        case .comfortable:
            return 8
        case .compact:
            return 8
        }
    }

    /// Spacing between the title and the subtitle line.
    public var titleSubtitleSpacing: CGFloat {
        switch self {
        case .comfortable:
            return 8
        case .compact:
            return 4
        }
    }

    /// Extra relative font-size adjustment folded into the post text on top of
    /// the user's text-scale preference. Compact shaves a point.
    public var relativeFontSizeAdjustment: CGFloat {
        switch self {
        case .comfortable:
            return 0
        case .compact:
            return -1
        }
    }
}
