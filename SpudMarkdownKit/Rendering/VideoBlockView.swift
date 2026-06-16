//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// A video embed rendered as a 16:9 dark poster tile with a centered play
/// button and a static faux transport bar. Tapping forwards the URL to the host
/// (the real AVPlayer is wired at integration).
final class VideoBlockView: UIView {
    private let url: URL
    private let onTap: ((URL) -> Void)?

    init(url: URL, context: MarkdownContext, onTap: ((URL) -> Void)?) {
        self.url = url
        self.onTap = onTap
        super.init(frame: .zero)
        let post = context.kind == .post

        layer.cornerRadius = post ? 12 : 9
        clipsToBounds = true
        backgroundColor = .black

        // 16:9 poster plate (no real poster in the Lab).
        let poster = UIView()
        poster.backgroundColor = UIColor(white: 0.12, alpha: 1)
        poster.translatesAutoresizingMaskIntoConstraints = false
        addSubview(poster)
        NSLayoutConstraint.activate([
            poster.topAnchor.constraint(equalTo: topAnchor),
            poster.bottomAnchor.constraint(equalTo: bottomAnchor),
            poster.leadingAnchor.constraint(equalTo: leadingAnchor),
            poster.trailingAnchor.constraint(equalTo: trailingAnchor),
            poster.heightAnchor.constraint(equalTo: poster.widthAnchor, multiplier: 9.0 / 16.0),
        ])

        // Centered play button.
        let diameter: CGFloat = post ? 56 : 44
        let circle = UIView()
        circle.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        circle.layer.cornerRadius = diameter / 2
        circle.layer.borderWidth = 1.5
        circle.layer.borderColor = UIColor.white.withAlphaComponent(0.8).cgColor
        circle.translatesAutoresizingMaskIntoConstraints = false
        let playIcon = UIImageView(image: UIImage(systemName: "play.fill"))
        playIcon.tintColor = .white
        playIcon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: post ? 22 : 18)
        playIcon.translatesAutoresizingMaskIntoConstraints = false
        circle.addSubview(playIcon)
        addSubview(circle)
        NSLayoutConstraint.activate([
            circle.widthAnchor.constraint(equalToConstant: diameter),
            circle.heightAnchor.constraint(equalToConstant: diameter),
            circle.centerXAnchor.constraint(equalTo: poster.centerXAnchor),
            circle.centerYAnchor.constraint(equalTo: poster.centerYAnchor),
            playIcon.centerXAnchor.constraint(equalTo: circle.centerXAnchor, constant: 1),
            playIcon.centerYAnchor.constraint(equalTo: circle.centerYAnchor),
        ])

        // Bottom transport bar overlay.
        let bar = makeTransportBar(post: post, smallPointSize: context.smallFont.pointSize)
        addSubview(bar)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: poster.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: poster.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: poster.bottomAnchor),
        ])

        isAccessibilityElement = true
        accessibilityLabel = "Video"
        accessibilityHint = "Tap to play"
        accessibilityTraits = .button
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

    private func makeTransportBar(post: Bool, smallPointSize: CGFloat) -> UIView {
        let smallPlay = UIImageView(image: UIImage(systemName: "play.fill"))
        smallPlay.tintColor = .white
        smallPlay.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: post ? 15 : 13)
        smallPlay.setContentHuggingPriority(.required, for: .horizontal)

        let track = UIView()
        track.backgroundColor = UIColor.white.withAlphaComponent(0.3)
        track.layer.cornerRadius = 1.5
        track.translatesAutoresizingMaskIntoConstraints = false
        track.heightAnchor.constraint(equalToConstant: 3).isActive = true
        let fill = UIView()
        fill.backgroundColor = .white
        fill.layer.cornerRadius = 1.5
        fill.translatesAutoresizingMaskIntoConstraints = false
        track.addSubview(fill)
        NSLayoutConstraint.activate([
            fill.leadingAnchor.constraint(equalTo: track.leadingAnchor),
            fill.topAnchor.constraint(equalTo: track.topAnchor),
            fill.bottomAnchor.constraint(equalTo: track.bottomAnchor),
            fill.widthAnchor.constraint(equalTo: track.widthAnchor, multiplier: 0.24),
        ])

        let time = UILabel()
        time.text = "0:32 / 2:14"
        time.font = .monospacedSystemFont(ofSize: smallPointSize * 0.92, weight: .regular)
        time.textColor = .white
        time.setContentHuggingPriority(.required, for: .horizontal)
        time.setContentCompressionResistancePriority(.required, for: .horizontal)

        let speaker = UIImageView(image: UIImage(systemName: "speaker.wave.2.fill"))
        speaker.tintColor = .white
        speaker.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: post ? 16 : 14)
        speaker.setContentHuggingPriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [smallPlay, track, time, speaker])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 9
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: post ? 9 : 7, left: post ? 12 : 10, bottom: post ? 9 : 7, right: post ? 12 : 10)
        row.translatesAutoresizingMaskIntoConstraints = false

        let container = UIView()
        container.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: container.topAnchor),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        return container
    }
}
