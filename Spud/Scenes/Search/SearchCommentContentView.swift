//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import UIKit

/// The comment-result rendering: a comment body (up to three lines) above a
/// secondary one-line context line. Factored out of `SearchCommentCell` as a
/// plain `UIView` so the SAME rendering is hosted by both the Search results
/// cell (`SearchCommentCell`) and the Activity timeline's composed comment row
/// (`ActivityCommentRowCell`).
///
/// Why a `UIView` and not a nested `UITableViewCell`: a `UITableViewCell`'s own
/// `contentView` is attached by autoresizing mask, which severs the Auto Layout
/// height chain — embedding a whole comment cell inside another cell collapses
/// its content to ~0pt. A plain content view's intrinsic height propagates
/// through normal Auto Layout to whatever hosts it.
///
/// The view carries no internal margins: the text stack fills its bounds, so
/// the host decides insets by where it pins this view (the Search cell pins to
/// its content layout-margins guide; the Activity row aligns it under the verb
/// header).
final class SearchCommentContentView: UIView {
    private let contentLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 3
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    private let contextLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    init() {
        super.init(frame: .zero)

        let textStack = UIStackView(arrangedSubviews: [contentLabel, contextLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.spacing = 4

        addSubview(textStack)

        NSLayoutConstraint.activate([
            textStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            textStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            textStack.topAnchor.constraint(equalTo: topAnchor),
            textStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Renders a comment body above an arbitrary context line.
    func configure(content: String, context: String) {
        contentLabel.text = content
        contextLabel.text = context
    }

    /// Clears the rendered text so a recycled host starts clean. Called from the
    /// host cell's `prepareForReuse`.
    func prepareForReuse() {
        contentLabel.text = nil
        contextLabel.text = nil
    }
}
