//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// A small rounded badge overlaid on media thumbnails to label a content type —
/// either a short caption (e.g. "GIF", so an animated post reads as playable)
/// or an SF Symbol glyph (e.g. a globe for an external link). The inline
/// thumbnail shows a static frame / embed image; the badge signals the type.
final class MediaBadgeView: UIView {
    private let label: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .white
        label.font = .systemFont(ofSize: 10, weight: .bold)
        label.textAlignment = .center
        return label
    }()

    private let symbolView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .white
        imageView.isHidden = true
        return imageView
    }()

    /// The badge caption. Setting it to `nil` hides the text (and the badge when
    /// no symbol is set either). Mutually exclusive with `symbolName` in practice.
    var text: String? {
        didSet {
            label.text = text?.uppercased()
            label.isHidden = text == nil
            updateVisibility()
        }
    }

    /// An SF Symbol glyph for the badge (e.g. "globe"). Setting it to `nil` hides
    /// the glyph (and the badge when no text is set either).
    var symbolName: String? {
        didSet {
            symbolView.image = symbolName.map {
                UIImage(
                    systemName: $0,
                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .bold)
                )
            } ?? nil
            symbolView.isHidden = symbolName == nil
            updateVisibility()
        }
    }

    private func updateVisibility() {
        isHidden = text == nil && symbolName == nil
    }

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = UIColor.black.withAlphaComponent(0.6)
        layer.cornerRadius = 4
        layer.cornerCurve = .continuous
        isUserInteractionEnabled = false
        isHidden = true

        // The text and glyph occupy the same slot; only one is ever visible, and
        // the hidden one collapses so the pill sizes to the visible content.
        let stackView = UIStackView(arrangedSubviews: [label, symbolView])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .center

        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
