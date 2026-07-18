//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// A fixed-size community avatar for the share card. When a real icon image is
/// injected it fills a circle; otherwise it falls back to a tinted circle
/// bearing the community's initial — the hue derived deterministically from the
/// community handle (see ``ShareCardStyle/communityTintColor(forHandle:)``), so
/// the fallback is stable across runs.
///
/// Reused by both the post card header (``ShareCardHeaderView``) and — in
/// Task 3 — the comment-chain card's optional post header, so it lives in its
/// own file. The community is the card's public context and is NEVER redacted
/// (unlike a person avatar, which is — see ``ShareCardPersonView``).
final class ShareCardCommunityIconView: UIView {
    private let diameter: CGFloat
    private let letterLabel = UILabel()
    private let imageView = UIImageView()

    init(diameter: CGFloat) {
        self.diameter = diameter
        super.init(frame: .zero)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setUp() {
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = diameter / 2
        layer.cornerCurve = .continuous
        clipsToBounds = true

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.isHidden = true
        addSubview(imageView)

        letterLabel.translatesAutoresizingMaskIntoConstraints = false
        letterLabel.textAlignment = .center
        letterLabel.textColor = .white
        letterLabel.font = .systemFont(ofSize: diameter * 0.45, weight: .bold)
        addSubview(letterLabel)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: diameter),
            heightAnchor.constraint(equalToConstant: diameter),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            letterLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            letterLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    /// Configures the fallback tile from the community's display `name` (its
    /// initial) and `handle` (the deterministic hue source).
    func configure(name: String, handle: String) {
        let initial = name.first.map { String($0).uppercased() } ?? "?"
        letterLabel.text = initial
        backgroundColor = ShareCardStyle.communityTintColor(forHandle: handle)
    }

    /// Swaps to a loaded icon image (hiding the fallback tile), or back to the
    /// fallback when `image` is `nil`. Task 2 always renders the fallback
    /// (`ShareCardContent.PostSummary.communityIconUrl` is always `nil` today);
    /// this setter exists for a future builder that joins a real icon.
    func setImage(_ image: UIImage?) {
        imageView.image = image
        imageView.isHidden = image == nil
        letterLabel.isHidden = image != nil
        backgroundColor = image == nil ? backgroundColor : .clear
    }
}
