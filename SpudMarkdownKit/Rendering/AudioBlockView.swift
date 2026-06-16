//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// An audio embed rendered as a transport row: a teal play button, a static
/// faux waveform, and a duration label. Tapping forwards the URL to the host
/// (real playback is wired at integration).
final class AudioBlockView: UIView {
    private let url: URL
    private let onTap: ((URL) -> Void)?

    init(url: URL, context: MarkdownContext, onTap: ((URL) -> Void)?) {
        self.url = url
        self.onTap = onTap
        super.init(frame: .zero)
        let post = context.kind == .post

        backgroundColor = .secondarySystemFill
        layer.cornerRadius = post ? 12 : 9
        layer.borderWidth = 0.5
        layer.borderColor = UIColor.separator.cgColor
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: AudioBlockView, _: UITraitCollection) in
            view.layer.borderColor = UIColor.separator.cgColor
        }

        let diameter: CGFloat = post ? 38 : 32
        let playCircle = UIView()
        playCircle.backgroundColor = context.accentColor
        playCircle.layer.cornerRadius = diameter / 2
        playCircle.translatesAutoresizingMaskIntoConstraints = false
        playCircle.setContentHuggingPriority(.required, for: .horizontal)
        let playIcon = UIImageView(image: UIImage(systemName: "play.fill"))
        playIcon.tintColor = .white
        playIcon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: post ? 16 : 13)
        playIcon.translatesAutoresizingMaskIntoConstraints = false
        playCircle.addSubview(playIcon)
        NSLayoutConstraint.activate([
            playCircle.widthAnchor.constraint(equalToConstant: diameter),
            playCircle.heightAnchor.constraint(equalToConstant: diameter),
            playIcon.centerXAnchor.constraint(equalTo: playCircle.centerXAnchor),
            playIcon.centerYAnchor.constraint(equalTo: playCircle.centerYAnchor),
        ])

        let waveform = AudioBlockView.makeWaveform(post: post, accent: context.accentColor)

        let time = UILabel()
        time.text = "0:48"
        time.font = .monospacedSystemFont(ofSize: context.smallFont.pointSize, weight: .regular)
        time.textColor = context.secondaryColor
        time.setContentHuggingPriority(.required, for: .horizontal)
        time.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [playCircle, waveform, time])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = post ? 12 : 9
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: post ? 10 : 8, left: post ? 13 : 10, bottom: post ? 10 : 8, right: post ? 13 : 10)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        isUserInteractionEnabled = true
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    @objc
    private func tapped() {
        onTap?(url)
    }

    /// A static waveform: N bars of height `5 + |sin(i·1.7)|·(maxH−5)`, the first
    /// third tinted teal ("played"), the rest separator-colored.
    private static func makeWaveform(post: Bool, accent: UIColor) -> UIView {
        let barCount = post ? 34 : 26
        let playedCount = post ? 11 : 8
        let maxHeight: CGFloat = post ? 20 : 16

        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.distribution = .fillEqually
        row.spacing = 2
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: maxHeight + 2).isActive = true
        for i in 0..<barCount {
            let bar = UIView()
            bar.backgroundColor = i < playedCount ? accent : .separator
            bar.layer.cornerRadius = 1
            bar.translatesAutoresizingMaskIntoConstraints = false
            let height = 5 + abs(sin(Double(i) * 1.7)) * Double(maxHeight - 5)
            bar.heightAnchor.constraint(equalToConstant: CGFloat(height)).isActive = true
            row.addArrangedSubview(bar)
        }
        return row
    }
}
