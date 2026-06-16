//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudUIKit
import UIKit

/// A fenced code block: a rounded container with a header (language label + a
/// Copy affordance) over a horizontally-scrolling, non-wrapping monospaced body.
final class CodeBlockView: UIView {
    private let code: String

    init(language: String?, code: String, context: MarkdownContext) {
        self.code = code
        super.init(frame: .zero)

        backgroundColor = .secondarySystemFill
        layer.cornerRadius = context.kind == .post ? 12 : 9
        layer.borderWidth = 0.5
        layer.borderColor = UIColor.separator.cgColor

        let header = UIView()
        header.translatesAutoresizingMaskIntoConstraints = false

        let lang = UILabel()
        lang.text = (language ?? "text").lowercased()
        lang.font = .monospacedSystemFont(ofSize: context.smallFont.pointSize * 0.92, weight: .semibold)
        lang.textColor = .secondaryLabel
        lang.translatesAutoresizingMaskIntoConstraints = false

        let copy = UIButton(type: .system)
        copy.setTitle("Copy", for: .normal)
        copy.setImage(UIImage(systemName: "doc.on.doc"), for: .normal)
        copy.titleLabel?.font = .systemFont(ofSize: context.smallFont.pointSize * 0.92, weight: .semibold)
        copy.tintColor = context.accentColor
        copy.translatesAutoresizingMaskIntoConstraints = false
        copy.addAction(UIAction { [weak self] _ in self?.copyCode() }, for: .touchUpInside)

        header.addSubview(lang)
        header.addSubview(copy)

        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let body = UILabel()
        body.numberOfLines = 0
        body.text = code
        body.font = context.inlineCodeFont
        body.textColor = .label
        body.lineBreakMode = .byClipping
        body.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(body)

        let divider = UIView()
        divider.backgroundColor = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        addSubview(header)
        addSubview(divider)
        addSubview(scroll)

        let hPad: CGFloat = context.kind == .post ? 12 : 10
        let vPad: CGFloat = context.kind == .post ? 7 : 5
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor),
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            lang.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: hPad),
            lang.topAnchor.constraint(equalTo: header.topAnchor, constant: vPad),
            lang.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -vPad),
            copy.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -hPad),
            copy.centerYAnchor.constraint(equalTo: lang.centerYAnchor),
            divider.topAnchor.constraint(equalTo: header.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 0.5),
            scroll.topAnchor.constraint(equalTo: divider.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            body.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: vPad + 3),
            body.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -(vPad + 3)),
            body.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: hPad),
            body.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: hPad),
            scroll.heightAnchor.constraint(equalTo: body.heightAnchor, constant: (vPad + 3) * 2),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    private func copyCode() {
        UIPasteboard.general.string = code
        Haptics.tap()
    }
}
