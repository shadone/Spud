//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// The "Open in Spud" row shown at the top of Search when the query is a
/// recognized Lemmy URL. Leading arrow glyph, a primary "Open {kind} in Spud"
/// label, the URL as a secondary label, and a disclosure chevron.
final class SearchOpenURLCell: UITableViewCell {
    static let reuseIdentifier = "SearchOpenURLCell"

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        accessoryType = .disclosureIndicator
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(kind: SearchURLSuggestion.Kind, displayURL: String) {
        var content = UIListContentConfiguration.subtitleCell()
        content.image = UIImage(systemName: "arrow.up.forward.app")
        content.text = String(
            format: NSLocalizedString(
                "Open %@ in Spud",
                comment: "Search row that opens a pasted Lemmy URL; %@ is the object kind (post/community/etc.)"
            ),
            Self.kindNoun(kind)
        )
        content.secondaryText = displayURL
        content.secondaryTextProperties.color = .secondaryLabel
        content.secondaryTextProperties.lineBreakMode = .byTruncatingMiddle
        contentConfiguration = content
    }

    private static func kindNoun(_ kind: SearchURLSuggestion.Kind) -> String {
        switch kind {
        case .post: return NSLocalizedString("post", comment: "Lemmy object kind: post")
        case .comment: return NSLocalizedString("comment", comment: "Lemmy object kind: comment")
        case .community: return NSLocalizedString("community", comment: "Lemmy object kind: community")
        case .user: return NSLocalizedString("user", comment: "Lemmy object kind: user")
        case .instance: return NSLocalizedString("instance", comment: "Lemmy object kind: instance")
        }
    }
}
