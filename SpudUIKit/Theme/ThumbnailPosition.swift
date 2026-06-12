//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// Where the post-list thumbnail sits relative to the text column, or whether
/// it is shown at all.
///
/// `.left` reproduces the pre-M8 layout (thumbnail leading the text). `.right`
/// moves it to the trailing edge. `.hidden` drops the thumbnail entirely,
/// giving the title and subtitle the full width.
public enum ThumbnailPosition: String, CaseIterable, Codable, Sendable, Identifiable {
    case left
    case right
    case hidden

    public var id: String {
        rawValue
    }

    /// Whether the thumbnail should be laid out at all.
    public var showsThumbnail: Bool {
        self != .hidden
    }

    /// Human-readable name for the settings picker.
    public var title: String {
        switch self {
        case .left:
            return "Left"
        case .right:
            return "Right"
        case .hidden:
            return "Hidden"
        }
    }

    /// SF Symbol representing this position in the settings picker.
    public var symbolName: String {
        switch self {
        case .left:
            return "rectangle.lefthalf.inset.filled"
        case .right:
            return "rectangle.righthalf.inset.filled"
        case .hidden:
            return "rectangle.slash"
        }
    }
}
