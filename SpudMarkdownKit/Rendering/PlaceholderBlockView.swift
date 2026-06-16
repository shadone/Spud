//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// A muted placeholder for block kinds rendered in a later phase (code, table,
/// spoiler, image, audio, video, footnotes).
final class PlaceholderBlockView: UIView {
    init(label: String) {
        super.init(frame: .zero)
        backgroundColor = .secondarySystemFill
        layer.cornerRadius = 8
        let text = UILabel()
        text.text = "[\(label)]"
        text.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        text.textColor = .secondaryLabel
        text.translatesAutoresizingMaskIntoConstraints = false
        addSubview(text)
        NSLayoutConstraint.activate([
            text.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            text.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            text.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            text.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }
}
