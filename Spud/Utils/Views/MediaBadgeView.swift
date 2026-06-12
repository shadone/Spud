//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// A small rounded badge overlaid on media thumbnails to label a media type
/// (e.g. "GIF"), so an animated post is recognisable at a glance in the feed —
/// the inline thumbnail shows a static frame, the badge signals it plays.
final class MediaBadgeView: UIView {
    private let label: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .white
        label.font = .systemFont(ofSize: 10, weight: .bold)
        label.textAlignment = .center
        return label
    }()

    /// The badge caption. Setting it to `nil` hides the badge.
    var text: String? {
        didSet {
            label.text = text?.uppercased()
            isHidden = text == nil
        }
    }

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = UIColor.black.withAlphaComponent(0.6)
        layer.cornerRadius = 4
        layer.cornerCurve = .continuous
        isUserInteractionEnabled = false
        isHidden = true

        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
