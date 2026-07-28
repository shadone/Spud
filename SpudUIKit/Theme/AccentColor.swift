//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SwiftUI
import UIKit

/// A curated accent-color palette the user can choose from. The default,
/// ``lemmy``, matches Lemmy's brand green-ish teal. Each case resolves to a
/// concrete `UIColor` (and SwiftUI `Color`) via a pure function so it can be
/// unit-tested without touching UIKit appearance state.
public enum AccentColor: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Lemmy-ish default accent.
    case lemmy
    case blue
    case indigo
    case purple
    case pink
    case red
    case orange
    case green
    case teal

    public var id: String {
        rawValue
    }

    /// The concrete tint color. Pure and deterministic — safe to unit-test.
    public var color: UIColor {
        switch self {
        case .lemmy:
            // Lemmy brand teal/green. A single fixed hue (looks right on both
            // light and dark); the rest of the palette uses the system colors,
            // which already adapt per interface style.
            return UIColor(red: 0.0, green: 0.59, blue: 0.53, alpha: 1.0)
        case .blue:
            return .systemBlue
        case .indigo:
            return .systemIndigo
        case .purple:
            return .systemPurple
        case .pink:
            return .systemPink
        case .red:
            return .systemRed
        case .orange:
            return .systemOrange
        case .green:
            return .systemGreen
        case .teal:
            return .systemTeal
        }
    }

    public var swiftUIColor: Color {
        Color(color)
    }

    /// The accent as **foreground content** — text, or a glyph that carries
    /// meaning — on a non-accent background.
    ///
    /// Separate from ``color`` because the two jobs have opposite requirements:
    /// a fill wants the vivid swatch, a foreground wants enough luminance
    /// distance from the surface behind it to be readable. Several accents are
    /// far too light to be read on the app's light backgrounds as-is; this is
    /// the luminance-corrected variant, derived (not hand-picked) by
    /// ``AccentContentColor``. It is a **dynamic** colour, so Light and Dark
    /// each resolve to their own corrected value.
    ///
    /// Use it wherever the accent is drawn *as* content. Do **not** use it for
    /// a surface the accent fills — a vote capsule, a swipe track, a
    /// prominent button — those stay ``color``.
    public var contentColor: UIColor {
        AccentContentColor.dynamic(from: color)
    }

    /// ``contentColor`` for SwiftUI.
    public var swiftUIContentColor: Color {
        Color(contentColor)
    }

    /// Human-readable name for the settings picker.
    public var title: String {
        switch self {
        case .lemmy:
            return "Lemmy"
        case .blue:
            return "Blue"
        case .indigo:
            return "Indigo"
        case .purple:
            return "Purple"
        case .pink:
            return "Pink"
        case .red:
            return "Red"
        case .orange:
            return "Orange"
        case .green:
            return "Green"
        case .teal:
            return "Teal"
        }
    }
}
