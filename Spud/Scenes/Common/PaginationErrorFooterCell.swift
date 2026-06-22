//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// Footer shown when loading the next page failed. Tapping "Retry" re-runs the
/// pagination fetch.
final class PaginationErrorFooterCell: UITableViewCell {
    static let reuseIdentifier = "PaginationErrorFooterCell"

    var onRetry: (() -> Void)?

    private lazy var button: UIButton = {
        var config = UIButton.Configuration.plain()
        config.title = NSLocalizedString("Couldn't load more. Retry", comment: "Pagination failed footer action")
        config.image = UIImage(systemName: "arrow.clockwise")
        config.imagePadding = 6
        let button = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in
            self?.onRetry?()
        })
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        contentView.addSubview(button)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            button.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            button.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
        ])
        selectionStyle = .none
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
