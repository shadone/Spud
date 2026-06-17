//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// Explorer-score donut: a track ring + a coloured progress arc with the score
/// (0...100) and a "SCORE" caption centred inside.
final class InstanceScoreRingView: UIView {
    private let track = CAShapeLayer()
    private let progress = CAShapeLayer()
    private let valueLabel = UILabel()
    private var score100: Double?

    init() {
        super.init(frame: .zero)
        track.fillColor = UIColor.clear.cgColor
        track.strokeColor = UIColor.separator.cgColor
        track.lineWidth = 4
        progress.fillColor = UIColor.clear.cgColor
        progress.lineWidth = 4
        progress.lineCap = .round
        layer.addSublayer(track)
        layer.addSublayer(progress)

        valueLabel.textAlignment = .center
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 19, weight: .heavy)
        let caption = UILabel()
        caption.text = "SCORE"
        caption.textAlignment = .center
        caption.font = .systemFont(ofSize: 8, weight: .bold)
        caption.textColor = .tertiaryLabel
        let stack = UIStackView(arrangedSubviews: [valueLabel, caption])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(score100: Double?, color: UIColor) {
        self.score100 = score100
        if let score100 {
            valueLabel.text = "\(Int(score100.rounded()))"
            valueLabel.textColor = .label
        } else {
            valueLabel.text = "—"
            valueLabel.textColor = .tertiaryLabel
        }
        progress.strokeColor = color.cgColor
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = min(bounds.width, bounds.height)
        let radius = (size - track.lineWidth) / 2
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let path = UIBezierPath(
            arcCenter: center,
            radius: radius,
            startAngle: -.pi / 2,
            endAngle: 1.5 * .pi,
            clockwise: true
        )
        track.path = path.cgPath
        progress.path = path.cgPath
        progress.strokeEnd = score100.map { max(0, min(1, $0 / 100)) } ?? 0
        valueLabel.font = .monospacedDigitSystemFont(ofSize: size * 0.34, weight: .heavy)
    }
}
