//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import UIKit

/// A horizontally-scrolling row of filter chip buttons, one per
/// `ActivityFilterType`. Active chips fill with the accent tint; inactive chips
/// are outlined.
class ActivityFilterBarView: UIScrollView {
    var onToggleFilter: ((ActivityFilterType) -> Void)?

    var activeFilters: Set<ActivityFilterType> = [] {
        didSet { updateChipStates() }
    }

    // MARK: Private

    private var chipButtons: [ActivityFilterType: UIButton] = [:]

    // MARK: Functions

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Private

    private func setup() {
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        alwaysBounceHorizontal = true

        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor, constant: -8),
            stack.heightAnchor.constraint(equalTo: frameLayoutGuide.heightAnchor, constant: -16),
        ])

        for filter in ActivityFilterType.allCases {
            let button = makeChipButton(for: filter)
            chipButtons[filter] = button
            stack.addArrangedSubview(button)
        }
    }

    private func makeChipButton(for filter: ActivityFilterType) -> UIButton {
        var config = UIButton.Configuration.bordered()
        config.title = filter.displayName
        config.image = UIImage(systemName: filter.systemImageName)
        config.imagePadding = 4
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
        config.cornerStyle = .capsule
        config.baseForegroundColor = .label
        config.baseBackgroundColor = .secondarySystemFill

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addAction(UIAction { [weak self, filter] _ in
            self?.onToggleFilter?(filter)
        }, for: .touchUpInside)
        return button
    }

    private func updateChipStates() {
        for (filter, button) in chipButtons {
            let isActive = activeFilters.contains(filter)
            var config = button.configuration ?? UIButton.Configuration.bordered()
            if isActive {
                config.baseForegroundColor = .white
                config.baseBackgroundColor = .tintColor
            } else {
                config.baseForegroundColor = .label
                config.baseBackgroundColor = .secondarySystemFill
            }
            button.configuration = config
        }
    }
}

private extension ActivityFilterType {
    var displayName: String {
        switch self {
        case .post: NSLocalizedString("Posts", comment: "Activity filter: authored posts")
        case .comment: NSLocalizedString("Comments", comment: "Activity filter: authored comments")
        case .save: NSLocalizedString("Saved", comment: "Activity filter: saved content")
        case .vote: NSLocalizedString("Voted", comment: "Activity filter: voted content")
        case .read: NSLocalizedString("Read", comment: "Activity filter: opened posts")
        case .seen: NSLocalizedString("Seen", comment: "Activity filter: scrolled-past posts")
        case .hide: NSLocalizedString("Hidden", comment: "Activity filter: hidden posts")
        }
    }

    var systemImageName: String {
        switch self {
        case .post: "doc.text"
        case .comment: "text.bubble"
        case .save: "bookmark"
        case .vote: "arrow.up"
        case .read: "book"
        case .seen: "eye"
        case .hide: "eye.slash"
        }
    }
}
