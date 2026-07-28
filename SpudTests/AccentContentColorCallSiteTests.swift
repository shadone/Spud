//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUIKit
import Testing
import UIKit
@testable import Spud

/// Contrast coverage for the accent-as-content **call sites**, as opposed to
/// ``AccentContentColorTests`` in SpudUIKitTests, which covers the token.
///
/// The token clearing AA on paper is not the same claim as a screen clearing
/// it: a site can pick the right colour and still fail because it draws it on
/// the accent's own wash, and a site can pick the wrong colour and look fine on
/// the default accent. These build the real views and measure the real pairing,
/// for all nine accents in both appearances.
@MainActor
struct AccentContentColorCallSiteTests {
    private static let styles: [UIUserInterfaceStyle] = [.light, .dark]

    private static func describe(_ accent: AccentColor, _ style: UIUserInterfaceStyle) -> Comment {
        "\(accent.rawValue) / \(style == .light ? "light" : "dark")"
    }

    private static func traits(_ style: UIUserInterfaceStyle) -> UITraitCollection {
        UITraitCollection(userInterfaceStyle: style)
    }

    /// Composites `color` (which may be translucent) over `background` and
    /// returns the opaque result — WCAG is defined over composited pixels, so a
    /// wash has to be flattened before it means anything.
    private static func flatten(_ color: UIColor, over background: UIColor, in traits: UITraitCollection) -> UIColor {
        var fr: CGFloat = 0, fg: CGFloat = 0, fb: CGFloat = 0, fa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        _ = color.resolvedColor(with: traits).getRed(&fr, green: &fg, blue: &fb, alpha: &fa)
        _ = background.resolvedColor(with: traits).getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return UIColor(
            red: fr * fa + br * (1 - fa),
            green: fg * fa + bg * (1 - fa),
            blue: fb * fa + bb * (1 - fa),
            alpha: 1
        )
    }

    private static func firstLabel(in view: UIView) -> UILabel? {
        if let label = view as? UILabel { return label }
        for subview in view.subviews {
            if let match = firstLabel(in: subview) { return match }
        }
        return nil
    }

    // MARK: - The mechanism the UIKit call sites depend on

    /// Several call sites derive their content accent from the **inherited view
    /// tint** (`AccentContentColor.dynamic(from: tintColor)`) rather than from
    /// `ThemeManager`, because the tint is what a snapshot fixture pins.
    ///
    /// That only works if `UIView.tintColor` hands back the *dynamic* colour it
    /// was assigned rather than a value already flattened for the current
    /// appearance — otherwise every one of those sites would silently bake in
    /// one appearance and be wrong after the user switched. This pins that
    /// behaviour so a UIKit change cannot break it invisibly.
    @Test
    func inheritedViewTintStaysDynamic() throws {
        let parent = UIView()
        let child = UIView()
        parent.addSubview(child)
        parent.tintColor = AccentColor.orange.color

        let inherited = try #require(child.tintColor)
        #expect(
            inherited.resolvedColor(with: Self.traits(.light))
                != inherited.resolvedColor(with: Self.traits(.dark)),
            """
            UIView.tintColor no longer preserves a dynamic colour. Every call site using \
            AccentContentColor.dynamic(from: tintColor) now bakes in one appearance - \
            switch them to ThemeManager.currentContentAccentColor.
            """
        )

        let derived = AccentContentColor.dynamic(from: inherited)
        #expect(
            derived.resolvedColor(with: Self.traits(.light))
                != derived.resolvedColor(with: Self.traits(.dark))
        )
    }

    // MARK: - Sites

    /// The comment "OP" badge: 11pt bold accent text on a 16% wash of the same
    /// accent. Measured as low as 1.89:1 before the split.
    @Test
    func opBadgeTextClearsAAForEveryAccent() throws {
        let badge = AuthorBadge(text: "OP", symbolName: nil, usesAccent: true, color: .systemTeal, solid: false)

        for accent in AccentColor.allCases {
            for style in Self.styles {
                let traits = Self.traits(style)
                let view = makeAuthorBadgeView(badge, accent: accent.color)
                let label = try #require(Self.firstLabel(in: view))
                let attributes = try #require(label.attributedText?.attributes(at: 0, effectiveRange: nil))
                let text = try #require(attributes[.foregroundColor] as? UIColor)
                let wash = try #require(label.backgroundColor)

                let background = Self.flatten(wash, over: .systemBackground, in: traits)
                let ratio = WCAGContrast.ratio(between: text, and: background, in: traits)
                #expect(
                    ratio >= WCAGContrast.aaNormalText,
                    """
                    OP badge text contrast \(ratio) is below AA (\(WCAGContrast.aaNormalText)) \
                    for \(Self.describe(accent, style))
                    """
                )
            }
        }
    }

    /// The post-detail "N new since your last visit" banner: the Jump control
    /// (17pt regular) and the "N new" run, both on an 11%/16% wash of the
    /// accent. The Jump title measured as low as 1.97:1 before the split.
    @Test
    func newSinceBannerContentClearsAAForEveryAccent() throws {
        for accent in AccentColor.allCases {
            for style in Self.styles {
                let traits = Self.traits(style)
                let cell = PostDetailNewSinceBannerCell(style: .default, reuseIdentifier: nil)
                cell.configure(count: 3, relativeText: "2 hours ago", accent: accent.color)

                let wash = try #require(cell.contentView.backgroundColor)
                let background = Self.flatten(wash, over: .systemBackground, in: traits)

                let jumpButton = try #require(
                    cell.contentView.firstDescendant(where: { $0 is UIButton }) as? UIButton
                )
                let jumpRatio = WCAGContrast.ratio(between: jumpButton.tintColor, and: background, in: traits)
                #expect(
                    jumpRatio >= WCAGContrast.aaNormalText,
                    """
                    "Jump" contrast \(jumpRatio) is below AA (\(WCAGContrast.aaNormalText)) \
                    for \(Self.describe(accent, style))
                    """
                )

                let messageLabel = try #require(Self.firstLabel(in: cell.contentView))
                let attributes = try #require(messageLabel.attributedText?.attributes(at: 0, effectiveRange: nil))
                let countColor = try #require(attributes[.foregroundColor] as? UIColor)
                let countRatio = WCAGContrast.ratio(between: countColor, and: background, in: traits)
                #expect(
                    countRatio >= WCAGContrast.aaNormalText,
                    """
                    "N new" contrast \(countRatio) is below AA (\(WCAGContrast.aaNormalText)) \
                    for \(Self.describe(accent, style))
                    """
                )
            }
        }
    }

    /// The upvoted "▲ N" score run in a feed cell's metadata line — accent text
    /// straight on the cell background, no wash to soften it.
    @Test
    func upvotedScoreTextClearsAAForEveryAccent() {
        let appearance = GeneralAppearance()
        let manager = ThemeManager.shared
        let original = manager.accent
        defer { manager.setAccent(original) }

        for accent in AccentColor.allCases {
            manager.setAccent(accent)
            let string = IconValueFormatter.attributedString(
                numberOfVotesOrScore: 42,
                voteStatus: .up,
                attributes: [.font: UIFont.preferredFont(forTextStyle: .body)],
                appearance: appearance
            )
            let color = string.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor

            for style in Self.styles {
                let traits = Self.traits(style)
                let ratio = WCAGContrast.ratio(between: color ?? .label, and: .systemBackground, in: traits)
                #expect(
                    ratio >= WCAGContrast.aaNormalText,
                    """
                    Upvoted score contrast \(ratio) is below AA (\(WCAGContrast.aaNormalText)) \
                    for \(Self.describe(accent, style))
                    """
                )
            }
        }
    }

    /// The vote **fill** is deliberately NOT corrected: the capsule is a
    /// surface, it carries white on top, and darkening it was tried and
    /// rejected. This pins the split so a later "make everything accessible"
    /// sweep cannot quietly take the fill with it.
    @Test
    func theVoteFillKeepsTheVividAccent() {
        let appearance = GeneralAppearance()
        let manager = ThemeManager.shared
        let original = manager.accent
        defer { manager.setAccent(original) }

        for accent in AccentColor.allCases {
            manager.setAccent(accent)
            for style in Self.styles {
                let traits = Self.traits(style)
                #expect(
                    appearance.upvoteButtonActiveColor.resolvedColor(with: traits)
                        == accent.color.resolvedColor(with: traits),
                    "the upvote fill was darkened for \(Self.describe(accent, style))"
                )
                #expect(
                    appearance.upvoteSwipeActionBackgroundColor.resolvedColor(with: traits)
                        == accent.color.resolvedColor(with: traits),
                    "the upvote swipe track was darkened for \(Self.describe(accent, style))"
                )
            }
        }
    }
}

private extension UIView {
    /// Depth-first search for the first descendant satisfying `predicate`.
    func firstDescendant(where predicate: (UIView) -> Bool) -> UIView? {
        for subview in subviews {
            if predicate(subview) { return subview }
            if let match = subview.firstDescendant(where: predicate) { return match }
        }
        return nil
    }
}
