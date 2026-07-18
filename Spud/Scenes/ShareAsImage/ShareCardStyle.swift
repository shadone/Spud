//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// Fixed geometry for the share card. The card is a designed, exported
/// artifact rendered off-screen at a constant width, so every metric here is a
/// literal point value — nothing scales with Dynamic Type or the device. See
/// the card visual spec in
/// `docs/superpowers/plans/2026-07-18-share-as-image.md`.
enum ShareCardMetrics {
    /// The card's fixed design width. Task 4's renderer draws the card at this
    /// width (× scale 3 for the exported PNG); the editor preview scales it to
    /// fit.
    static let width: CGFloat = 372
    /// Inner padding between the card's edge and its content.
    static let padding: CGFloat = 26
    /// The card's outer corner radius.
    static let cornerRadius: CGFloat = 20
    /// Thin divider/border line weight. A fixed value (not `1 / scale`) so the
    /// off-screen render is identical regardless of the rendering scale.
    static let hairline: CGFloat = 1

    /// Content width available inside the padding.
    static var contentWidth: CGFloat {
        width - 2 * padding
    }

    /// The media block's corner radius.
    static let mediaCornerRadius: CGFloat = 12
    /// Media height as a fraction of the content width for a normal-aspect
    /// image.
    static let mediaHeightRatio: CGFloat = 0.72
    /// Media height fraction for a wide image (aspect wider than 4:3) — the
    /// card relaxes to a shorter block so a panorama doesn't dominate.
    static let mediaWideHeightRatio: CGFloat = 0.52

    /// Community icon diameter in the post-card header lockup.
    static let communityIconSize: CGFloat = 34
    /// Creator avatar diameter in the post-card header.
    static let creatorAvatarSize: CGFloat = 22
    /// Max width of the right-aligned creator lockup before its handle
    /// ellipsizes.
    static let creatorMaxWidth: CGFloat = 156

    /// Max height of a `.truncate` body before it fades out.
    static let truncatedBodyMaxHeight: CGFloat = 132
    /// Height of the bottom fade applied to a truncated body.
    static let bodyFadeHeight: CGFloat = 46
}

/// The card's fixed type ramp. Deliberately built from `UIFont.systemFont` /
/// `monospacedSystemFont` at literal sizes — never `preferredFont` — because
/// the card ignores Dynamic Type by design (a shared image must look identical
/// regardless of the sharer's text-size setting).
enum ShareCardFonts {
    static let communityName = UIFont.systemFont(ofSize: 15, weight: .bold)
    static let communityHandle = UIFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
    static let creatorHandle = UIFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
    static let title = UIFont.systemFont(ofSize: 22, weight: .heavy)
    static let body = UIFont.systemFont(ofSize: 15, weight: .regular)
    static let readMore = UIFont.systemFont(ofSize: 12.5, weight: .bold)
    static let statValue = UIFont.monospacedSystemFont(ofSize: 13, weight: .medium)
    static let timestamp = UIFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
    static let permalink = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    static let viaLabel = UIFont.systemFont(ofSize: 12.5, weight: .regular)
    static let viaWordmark = UIFont.systemFont(ofSize: 12.5, weight: .heavy)
    static let mediaCaption = UIFont.systemFont(ofSize: 12.5, weight: .medium)
    static let sensitiveLabel = UIFont.systemFont(ofSize: 12.5, weight: .bold)
    static let postHeaderTitle = UIFont.systemFont(ofSize: 16.5, weight: .heavy)
}

/// Formatting and deterministic-color helpers shared by the card views.
enum ShareCardStyle {
    /// The card's absolute timestamp: `dateStyle: .medium, timeStyle: .short`
    /// (e.g. "Jul 12, 2026 at 4:03 PM"). Built locally per call — never a
    /// `static let` — per the codebase's non-Sendable-formatter convention.
    ///
    /// `locale`/`timeZone` are a test seam: production passes `.current` so the
    /// sharer's device settings drive the rendering, while snapshot tests pin
    /// `en_US_POSIX`/`GMT` so a recorded reference never depends on the running
    /// machine's locale or zone.
    static func timestampString(_ date: Date, locale: Locale, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// A stable tint for a community's fallback initial-tile, derived
    /// deterministically from its handle so the same community always reads the
    /// same color across runs (snapshot references depend on this being
    /// deterministic). Uses the same djb2 hash + saturation/brightness as the
    /// app's `CommunityHueIcon`, keyed on the qualified handle rather than the
    /// bare name.
    static func communityTintColor(forHandle handle: String) -> UIColor {
        var hash: UInt64 = 5381
        for byte in handle.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        let hue = CGFloat(hash % 360) / 360
        return UIColor(hue: hue, saturation: 0.5, brightness: 0.6, alpha: 1)
    }

    /// A paragraph style with a fixed line-height multiple, for the card's
    /// fixed-metric text blocks (title ~1.18, body ~1.58).
    static func paragraphStyle(lineHeightMultiple: CGFloat, alignment: NSTextAlignment = .natural) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = lineHeightMultiple
        style.alignment = alignment
        return style
    }
}
