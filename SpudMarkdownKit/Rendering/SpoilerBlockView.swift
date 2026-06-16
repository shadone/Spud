//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// A spoiler: a tappable disclosure header over a collapsible stack of the
/// spoiler's nested block views. Starts collapsed.
final class SpoilerBlockView: UIView {
    private let bodyStack = UIStackView()
    private let chevron = UIImageView()
    private var expanded = false
    private let onContentSizeChange: (() -> Void)?

    init(
        title: [MarkdownInline],
        children: [MarkdownBlock],
        context: MarkdownContext,
        renderer: MarkdownBlockRenderer
    ) {
        onContentSizeChange = renderer.onContentSizeChange
        super.init(frame: .zero)
        backgroundColor = .secondarySystemFill
        layer.cornerRadius = context.kind == .post ? 10 : 8
        clipsToBounds = true

        let header = UIStackView()
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 8
        header.isLayoutMarginsRelativeArrangement = true
        let hPad: CGFloat = context.kind == .post ? 13 : 10
        let vPad: CGFloat = context.kind == .post ? 10 : 8
        header.layoutMargins = UIEdgeInsets(top: vPad, left: hPad, bottom: vPad, right: hPad)
        header.translatesAutoresizingMaskIntoConstraints = false

        chevron.image = UIImage(systemName: "chevron.right")
        chevron.tintColor = context.accentColor
        chevron.setContentHuggingPriority(.required, for: .horizontal)

        let titleLabel = UILabel()
        titleLabel.numberOfLines = 0
        if title.isEmpty {
            titleLabel.text = "Spoiler"
            titleLabel.font = .italicSystemFont(ofSize: context.bodyFont.pointSize)
            titleLabel.textColor = context.secondaryColor
        } else {
            let attributed = NSMutableAttributedString(
                attributedString: InlineAttributedStringBuilder.build(title, context: context)
            )
            attributed.addAttributes(
                [.font: context.bodyFont.withTraits(.traitBold), .foregroundColor: context.labelColor],
                range: NSRange(location: 0, length: attributed.length)
            )
            titleLabel.attributedText = attributed
        }
        header.addArrangedSubview(chevron)
        header.addArrangedSubview(titleLabel)

        bodyStack.axis = .vertical
        bodyStack.spacing = context.interBlockGap
        bodyStack.isLayoutMarginsRelativeArrangement = true
        bodyStack.layoutMargins = UIEdgeInsets(top: 0, left: hPad, bottom: vPad, right: hPad)
        for view in renderer.views(for: children) {
            bodyStack.addArrangedSubview(view)
        }
        bodyStack.isHidden = true

        let container = UIStackView(arrangedSubviews: [header, bodyStack])
        container.axis = .vertical
        container.translatesAutoresizingMaskIntoConstraints = false
        addSubview(container)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: topAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        header.isUserInteractionEnabled = true
        header.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(toggle)))
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    @objc
    private func toggle() {
        expanded.toggle()
        bodyStack.isHidden = !expanded
        chevron.image = UIImage(systemName: expanded ? "chevron.down" : "chevron.right")
        onContentSizeChange?()
    }
}
