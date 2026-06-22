//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// Base class for pulsing skeleton placeholder views. Provides the shared,
/// reduce-motion-aware opacity pulse and a neutral rounded "bar" factory used to
/// build skeleton rows. Subclasses lay out their own bars.
class SkeletonView: UIView {
    /// Starts the pulse, unless Reduce Motion is on (then the bars stay static).
    func startAnimating() {
        layer.removeAnimation(forKey: "pulse")
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.45
        pulse.duration = 0.8
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(pulse, forKey: "pulse")
    }

    func stopAnimating() {
        layer.removeAnimation(forKey: "pulse")
    }

    /// A neutral rounded bar used as a skeleton element. Callers may override the
    /// returned view's `layer.cornerRadius` for non-default shapes (e.g. a round
    /// avatar dot).
    static func bar(height: CGFloat) -> UIView {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .tertiarySystemFill
        view.layer.cornerRadius = min(height / 2, 6)
        view.layer.cornerCurve = .continuous
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }
}
