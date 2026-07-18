//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudUIKit
import UIKit

/// The share card's own two-surface color palette (light / dark), fixed and
/// theme-independent by design: the card is a piece of exported content, not
/// app chrome, so it must render identically regardless of the device's
/// current appearance, true-black setting, or accent-color preference. Never
/// substitute `ThemeManager.currentAccentColor` or `Theme.*` tokens here —
/// those read the process-wide true-black flag and would make the exported
/// image drift between devices/settings, defeating the point of a
/// deterministic, shareable card. Values are the design deck's exact
/// hex/rgba tokens (see `docs/superpowers/plans/2026-07-18-share-as-image.md`
/// "Card visual spec").
struct ShareCardPalette {
    /// Canvas backdrop behind the card (visible only in `.square`/`.story`
    /// canvas modes, or as the card's own edge on `.native`).
    let paper: UIColor
    /// The card's own background.
    let panel: UIColor
    /// Primary text color.
    let ink: UIColor
    /// Secondary text color (e.g. handles, byline).
    let sub: UIColor
    /// Tertiary text color (e.g. timestamps, permalink).
    let faint: UIColor
    /// Hairline border/divider color.
    let hair: UIColor
    /// Subtle fill for chip-like surfaces (e.g. the media-loading placeholder).
    let chip: UIColor
    /// The card's own outer hairline border color.
    let edge: UIColor

    /// `paper: #F7F5F1, panel: #FFFFFF, ink: #17181A, sub: rgba(23,24,26,0.56),
    /// faint: rgba(23,24,26,0.34), hair: rgba(0,0,0,0.10), chip: rgba(0,0,0,0.045),
    /// edge: rgba(0,0,0,0.06)`.
    static let light = ShareCardPalette(
        paper: UIColor(red: 0.9686, green: 0.9608, blue: 0.9451, alpha: 1),
        panel: UIColor(red: 1, green: 1, blue: 1, alpha: 1),
        ink: UIColor(red: 0.0902, green: 0.0941, blue: 0.1020, alpha: 1),
        sub: UIColor(red: 0.0902, green: 0.0941, blue: 0.1020, alpha: 0.56),
        faint: UIColor(red: 0.0902, green: 0.0941, blue: 0.1020, alpha: 0.34),
        hair: UIColor(red: 0, green: 0, blue: 0, alpha: 0.10),
        chip: UIColor(red: 0, green: 0, blue: 0, alpha: 0.045),
        edge: UIColor(red: 0, green: 0, blue: 0, alpha: 0.06)
    )

    /// `paper: #16171A, panel: #202227, ink: #F2F3F5, sub: rgba(236,238,242,0.62),
    /// faint: rgba(236,238,242,0.38), hair: rgba(255,255,255,0.11),
    /// chip: rgba(255,255,255,0.06), edge: rgba(255,255,255,0.05)`.
    static let dark = ShareCardPalette(
        paper: UIColor(red: 0.0863, green: 0.0902, blue: 0.1020, alpha: 1),
        panel: UIColor(red: 0.1255, green: 0.1333, blue: 0.1529, alpha: 1),
        ink: UIColor(red: 0.9490, green: 0.9529, blue: 0.9608, alpha: 1),
        sub: UIColor(red: 0.9255, green: 0.9333, blue: 0.9490, alpha: 0.62),
        faint: UIColor(red: 0.9255, green: 0.9333, blue: 0.9490, alpha: 0.38),
        hair: UIColor(red: 1, green: 1, blue: 1, alpha: 0.11),
        chip: UIColor(red: 1, green: 1, blue: 1, alpha: 0.06),
        edge: UIColor(red: 1, green: 1, blue: 1, alpha: 0.05)
    )

    /// The card's sole brand color, used only for the score triangle glyph,
    /// the "Read the full post on Lemmy" link, the chain destination rail +
    /// "SHARED" tag, and the "via Spud" logo glyph. Deliberately
    /// `AccentColor.lemmy`'s fixed literal, NOT the user's chosen
    /// `AccentColor` preference and NOT `ThemeManager.currentAccentColor` —
    /// the card's brand mark must stay Lemmy teal regardless of what accent
    /// color the user picked for the app chrome.
    static let teal: UIColor = AccentColor.lemmy.color
}

extension ShareCardOptions.Appearance {
    /// The fixed card palette this appearance renders with. Exhaustive over the
    /// two card surfaces — the card never follows the device's live appearance,
    /// so the resolution is a total mapping, not a "dark else light" fallback.
    /// The single place `ShareCardOptions.Appearance` becomes a
    /// ``ShareCardPalette``: `ShareCardView`, `ShareChainCardView`, and
    /// `ShareCardImageRenderer` all route through here.
    var palette: ShareCardPalette {
        switch self {
        case .light: .light
        case .dark: .dark
        }
    }
}
