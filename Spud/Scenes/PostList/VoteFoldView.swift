//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import UIKit

/// A folded-corner ("dog-ear") mark that carries voted state on a post-list
/// cell when the trailing vote arrows are hidden (gesture-voting mode). Up
/// folds from the trailing-top corner, down from the trailing-bottom corner —
/// orientation encodes direction before color does. Decorative: not an
/// accessibility element and not a tap target (voting stays a swipe/gesture).
final class VoteFoldView: UIView {
    private let triangleLayer = CAShapeLayer()
    private let arrow = UIImageView()
    private var status: VoteStatus = .neutral

    /// Fixed 28 pt corner; the fold is fixed geometry (unaffected by Dynamic Type).
    static let side: CGFloat = 28

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        layer.addSublayer(triangleLayer)
        arrow.contentMode = .center
        arrow.tintColor = VoteFillStyle.filledGlyphColor
        addSubview(arrow)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.side),
            heightAnchor.constraint(equalToConstant: Self.side),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Shows the fold for a voted status (hidden when neutral). `upColor` /
    /// `downColor` are the resolved vote tokens (accent / indigo).
    func configure(status: VoteStatus, upColor: UIColor, downColor: UIColor) {
        self.status = status
        switch status {
        case .neutral:
            isHidden = true
            return
        case .up:
            isHidden = false
            triangleLayer.fillColor = upColor.cgColor
            arrow.image = UIImage(
                systemName: "arrow.up",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 9, weight: .heavy)
            )
        case .down:
            isHidden = false
            triangleLayer.fillColor = downColor.cgColor
            arrow.image = UIImage(
                systemName: "arrow.down",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 9, weight: .heavy)
            )
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard status != .neutral else { return }
        let s = bounds.size
        let path = UIBezierPath()
        if status == .down {
            // Trailing-bottom corner: top-right, bottom-right, bottom-left.
            path.move(to: CGPoint(x: s.width, y: 0))
            path.addLine(to: CGPoint(x: s.width, y: s.height))
            path.addLine(to: CGPoint(x: 0, y: s.height))
            arrow.frame = CGRect(x: s.width - 15, y: s.height - 15, width: 13, height: 13)
        } else {
            // Trailing-top corner: top-left, top-right, bottom-right.
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: s.width, y: 0))
            path.addLine(to: CGPoint(x: s.width, y: s.height))
            arrow.frame = CGRect(x: s.width - 15, y: 2, width: 13, height: 13)
        }
        path.close()
        triangleLayer.path = path.cgPath
    }
}
