//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudUIKit
import UIKit

extension UIView {
    /// Briefly flashes a translucent accent tint over the view, then removes it,
    /// to re-anchor the user's eye - e.g. after an undo snaps the feed back to
    /// where they were. Honours Reduce Motion by fading faster. The flash is an
    /// opacity fade (not motion), so it stays on under that setting.
    func pulseHighlight(color: UIColor = ThemeManager.currentAccentColor) {
        let overlay = UIView()
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.backgroundColor = color.withAlphaComponent(0.22)
        overlay.isUserInteractionEnabled = false
        addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: topAnchor),
            overlay.bottomAnchor.constraint(equalTo: bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        let duration = UIAccessibility.isReduceMotionEnabled ? 0.3 : 0.6
        UIView.animate(withDuration: duration, delay: 0.05, options: .curveEaseOut) {
            overlay.alpha = 0
        } completion: { _ in
            overlay.removeFromSuperview()
        }
    }
}
