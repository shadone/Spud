//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SwiftUI
import UIKit

public extension Color {
    /// The active accent as **foreground content** — accent-coloured text, or a
    /// glyph that carries meaning — in SwiftUI.
    ///
    /// The counterpart of ``AccentColor/contentColor`` for views that would
    /// otherwise reach for `Color.accentColor`. Use it wherever the accent is
    /// drawn *as* content: `Color.accentColor` (and the inherited tint behind
    /// it) is the vivid fill, which several of the nine accents are far too
    /// light to be read in.
    ///
    /// Keep using `Color.accentColor` where the accent is the **surface** — a
    /// filled Subscribe pill, a Toggle's on-track, a `.borderedProminent`
    /// button — and for a low-alpha wash *behind* content.
    ///
    /// Backed by a provider that reads `ThemeManager` at resolve time rather
    /// than a value captured now, so it follows both an appearance change and
    /// an accent change.
    static var contentAccent: Color {
        Color(UIColor { traits in
            ThemeManager.currentContentAccentColor.resolvedColor(with: traits)
        })
    }
}
