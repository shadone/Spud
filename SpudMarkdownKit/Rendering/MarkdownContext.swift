//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudUIKit
import UIKit

/// The two body contexts: a full-width post body or a denser comment body.
public enum MarkdownContextKind: Sendable, Hashable { case post, comment }

/// Resolved sizing + color tokens for rendering a markdown body in one context.
/// Built on the main actor because it bakes `UIFont`s (Dynamic-Type scaled).
@MainActor
public struct MarkdownContext {
    public let kind: MarkdownContextKind
    /// Relative text-scale (the Display preference, roughly -3...+6 pt).
    public let textScale: CGFloat
    public let density: PostDensity

    /// Optional override for the primary body text color. When non-nil it
    /// replaces `labelColor` (and tints `secondaryColor`/`tertiaryColor` at
    /// reduced alpha) so a body rendered on a non-system fill — e.g. an
    /// accent-tinted DM chat bubble — stays high-contrast. `nil` keeps the
    /// system label colors (the default for posts and comments on the normal
    /// background).
    public let foregroundColorOverride: UIColor?

    /// Optional override for the link / accent color (links, mention &
    /// community chips, footnote markers). Pairs with `foregroundColorOverride`
    /// for the same high-contrast-on-tinted-fill reason (e.g. white links on an
    /// outgoing DM bubble). `nil` keeps the theme accent.
    public let linkColorOverride: UIColor?

    /// - Parameters:
    ///   - foregroundColorOverride: see `foregroundColorOverride`; pass a
    ///     contrasting color when rendering onto a non-system fill.
    ///   - linkColorOverride: see `linkColorOverride`.
    public init(
        kind: MarkdownContextKind,
        textScale: CGFloat = 0,
        density: PostDensity = .comfortable,
        foregroundColorOverride: UIColor? = nil,
        linkColorOverride: UIColor? = nil
    ) {
        self.kind = kind
        self.textScale = textScale
        self.density = density
        self.foregroundColorOverride = foregroundColorOverride
        self.linkColorOverride = linkColorOverride
    }

    private var post: Bool {
        kind == .post
    }

    private func scaled(
        _ base: CGFloat,
        weight: UIFont.Weight = .regular,
        textStyle: UIFont.TextStyle = .body
    ) -> UIFont {
        let font = UIFont.systemFont(ofSize: base + textScale + density.relativeFontSizeAdjustment, weight: weight)
        return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: font)
    }

    public var bodyFont: UIFont {
        scaled(post ? 15.5 : 14.5)
    }

    public var smallFont: UIFont {
        scaled(post ? 13 : 12)
    }

    public var inlineCodeFont: UIFont {
        UIFontMetrics(forTextStyle: .body).scaledFont(
            for: UIFont.monospacedSystemFont(ofSize: (post ? 14 : 12.5) + textScale + density.relativeFontSizeAdjustment, weight: .regular)
        )
    }

    public func headingFont(level: Int) -> UIFont {
        let base: CGFloat = post
            ? [29, 24, 20.5, 18, 16, 13.5][max(0, min(5, level - 1))]
            : [21, 19, 17.5, 16, 14.5, 12.5][max(0, min(5, level - 1))]
        let weight: UIFont.Weight = level <= 2 ? .heavy : .bold
        let style: UIFont.TextStyle = level <= 2 ? .title1 : (level <= 4 ? .title3 : .headline)
        return scaled(base, weight: weight, textStyle: style)
    }

    public var lineHeightMultiple: CGFloat {
        post ? 1.55 : 1.48
    }

    public var interBlockGap: CGFloat {
        post ? 15 : 9
    }

    public var listIndent: CGFloat {
        post ? 22 : 17
    }

    /// Colors
    public var labelColor: UIColor {
        foregroundColorOverride ?? .label
    }

    /// Secondary text (strikethrough, custom-emoji shorthand, H6, captions). When
    /// a foreground override is set we derive it from that color at reduced alpha
    /// so it tracks the override's contrast instead of falling back to the system
    /// secondary label (which would be near-invisible on a tinted fill).
    public var secondaryColor: UIColor {
        foregroundColorOverride?.withAlphaComponent(0.75) ?? .secondaryLabel
    }

    public var tertiaryColor: UIColor {
        foregroundColorOverride?.withAlphaComponent(0.55) ?? .tertiaryLabel
    }

    public var accentColor: UIColor {
        linkColorOverride ?? ThemeManager.currentAccentColor
    }

    public var inlineCodeForeground: UIColor {
        MarkdownColors.inlineCodeForeground
    }

    public var inlineCodeBackground: UIColor {
        .secondarySystemFill
    }

    public var highlightColor: UIColor {
        MarkdownColors.highlight
    }

    public var quoteBarColor: UIColor {
        // Track the foreground override (at a low alpha) so a blockquote's
        // leading bar stays visible on a tinted fill instead of fading into it.
        foregroundColorOverride?.withAlphaComponent(0.4) ?? .quaternaryLabel
    }

    public var chipBackground: UIColor {
        MarkdownColors.chipBackground
    }
}
