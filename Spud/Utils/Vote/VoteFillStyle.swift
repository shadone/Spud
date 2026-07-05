//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import UIKit

/// Shared styling for the "voted" state's filled capsule, used by every vote
/// surface (post-list arrow buttons, the detail-header vote button, and the
/// comment score-pill) so they read as one object.
///
/// The state is carried by a real weight change — a solid fill with a white
/// glyph vs a hairline/tertiary outline — not by hue alone, so it survives a
/// glance and color-blindness. Colors reuse the app's existing vote tokens
/// (accent for up, periwinkle for down) rather than hardcoded values, so the
/// upvote fill tracks the user's chosen accent.
@MainActor
enum VoteFillStyle {
    /// The fill color for a voted capsule, or `nil` when there is nothing to
    /// fill (neutral — the control stays a tertiary outline).
    static func fillColor(for status: VoteStatus, appearance: GeneralAppearance) -> UIColor? {
        switch status {
        case .up: return appearance.upvoteButtonActiveColor
        case .down: return appearance.downvoteButtonActiveColor
        case .neutral: return nil
        }
    }

    /// Glyph / number color drawn on top of a filled capsule.
    static let filledGlyphColor: UIColor = .white

    /// Corner radius of the filled capsule across all surfaces.
    static let capsuleCornerRadius: CGFloat = 8

    /// Animates a just-committed vote capsule: a light spring scale-in that
    /// reads as a pressed-button confirmation. Honors Reduce Motion by
    /// cross-fading the fill instead (no scaling).
    ///
    /// The vote haptic is fired elsewhere (on enqueue); this is visual only.
    static func animateCommit(_ view: UIView) {
        guard !UIAccessibility.isReduceMotionEnabled else {
            view.layer.removeAnimation(forKey: "voteFillFade")
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = 0.15
            view.layer.add(fade, forKey: "voteFillFade")
            return
        }
        view.layer.removeAnimation(forKey: "voteFillPop")
        let pop = CASpringAnimation(keyPath: "transform.scale")
        pop.fromValue = 0.9
        pop.toValue = 1.0
        pop.damping = 14
        pop.stiffness = 320
        pop.mass = 0.7
        pop.duration = pop.settlingDuration
        view.layer.add(pop, forKey: "voteFillPop")
    }
}
