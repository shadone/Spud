//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// Builds the two configurations of the post-detail "jump" floating action
/// button: the default next-top-level chevron, and the prominent "Next new"
/// capsule shown while there are new comments to jump to.
///
/// Extracted from `PostDetailViewController` so the rendered contrast of both
/// states can be measured directly in a test
/// (`PostDetailJumpButtonContrastTests`) instead of only through a whole
/// screen. That test is the reason this type exists — see the note below.
///
/// ## Why the prominent state is not accent-coloured
///
/// It used to be: `prominentGlass()` with `baseBackgroundColor` set to the
/// user's accent and `baseForegroundColor = .white`. Measured on
/// iPhone 17 Pro / iOS 26.3, that renders the 17pt regular title at **1.55:1 to
/// 4.41:1** depending on the accent (worst: Teal in dark, 1.55:1) — far under
/// the 4.5:1 WCAG AA bar for normal-size text.
///
/// Three measured facts drove the shape of this code, all of which are
/// counter-intuitive enough to be worth writing down:
///
/// 1. **`prominentGlass()` blends the foreground into its own background
///    tint — it never renders the colour you asked for.** `.white` came out as
///    a light tint of the background (e.g. rgb(131,255,255) on the Lemmy teal),
///    byte-identical to leaving `baseForegroundColor` unset; `.black` came out
///    as a *dark* tint of the background. Supplying the colour through
///    `attributedTitle` instead makes no difference — the numbers are identical.
///    So the label colour is not a lever at all. (Non-prominent `.glass()` is
///    the opposite: it honours `baseForegroundColor` exactly.)
/// 2. **The background is not a lever either, as long as it is a saturated
///    accent.** Because the label is derived from the background, the best
///    achievable ratio over the nine accents peaks at 4.41:1 and bottoms out at
///    1.55:1. Darkening the accent until the derived label clears 4.5:1 does
///    work numerically, but at that point Orange renders brown and Green
///    renders olive — the accent is no longer recognisably the accent.
/// 3. **Deleting the override is a no-op.** `prominentGlass()` already takes its
///    background from the inherited `tintColor`, which in this app *is* the
///    accent, so plain `prominentGlass()` measured byte-identical to the
///    version that set `baseBackgroundColor` explicitly. There was no
///    system default hiding underneath to fall back to.
///
/// Hence `.label`: the semantic maximum-contrast colour for the current
/// appearance (near-black in light, near-white in dark). The system derives its
/// inverse for the title, which measures **15.9:1 (light) / 16.0:1 (dark)** for
/// every accent, and the capsule itself sits at 16.7:1 / 18.9:1 against the
/// comment list behind it — so the control is both legible and easy to find.
/// It also tracks Increase Contrast on its own, which a hand-computed colour
/// would not. The cost is that this one control no longer carries the accent;
/// the state it signals is carried by the word "new" instead, which is the
/// stronger cue anyway (WCAG 1.4.1: colour is never the only carrier).
enum JumpButtonStyle {
    /// The default affordance: a non-prominent glass chevron that scrolls to the
    /// next top-level comment. `.label` on `.glass()` is honoured verbatim and
    /// measures 16.7:1 / 17.3:1.
    static func defaultConfiguration() -> UIButton.Configuration {
        var config = UIButton.Configuration.glass()
        config.image = UIImage(systemName: "chevron.down")
        config.cornerStyle = .capsule
        config.baseForegroundColor = .label
        config.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
        return config
    }

    /// The "Next new" affordance. The screen's one floating action, so
    /// prominence is reserved for this state: it is the primary next thing to do
    /// when new comments exist.
    static func newCommentConfiguration() -> UIButton.Configuration {
        var config = UIButton.Configuration.prominentGlass()
        config.title = NSLocalizedString("Next new", comment: "Jump to the next new comment")
        config.image = UIImage(systemName: "chevron.down")
        config.imagePlacement = .trailing
        config.imagePadding = 6
        config.cornerStyle = .capsule
        // Not the accent - see the type's doc comment. Do not "restore" the
        // accent here without re-running PostDetailJumpButtonContrastTests.
        config.baseBackgroundColor = .label
        config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
        return config
    }

    /// The configuration for a given state.
    static func configuration(isNew: Bool) -> UIButton.Configuration {
        isNew ? newCommentConfiguration() : defaultConfiguration()
    }

    /// The VoiceOver label matching `configuration(isNew:)`.
    static func accessibilityLabel(isNew: Bool) -> String {
        isNew
            ? NSLocalizedString(
                "Next new comment",
                comment: "VoiceOver: jump to the next new comment"
            )
            : NSLocalizedString(
                "Next top-level comment",
                comment: "Accessibility label for the jump-to-next-comment button"
            )
    }
}
