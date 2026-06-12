//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// Shared haptic-feedback helper. Every committal action (vote, save,
/// subscribe, send, collapse) should fire a haptic per the design north-star.
///
/// Each call prepares the generator immediately before firing so the Taptic
/// Engine is warmed up, minimising latency between the gesture and the tap.
/// All entry points are `@MainActor` because `UIFeedbackGenerator` must be
/// used from the main thread.
@MainActor
public enum Haptics {
    /// A light impact, for a discrete committal action (e.g. toggling save).
    public static func tap() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }

    /// A success notification, for an action that completed as intended.
    public static func success() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
    }

    /// A warning notification, for an action that was rejected or needs
    /// attention (e.g. a gated action a signed-out user attempted).
    public static func warning() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.warning)
    }
}
