//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// The footnotes section at the end of a body: a divider, a small uppercase
/// "Footnotes" header, and the numbered notes (each with a return affordance).
final class FootnotesBlockView: UIView {
    init(footnotes: [MarkdownFootnote], context: MarkdownContext, renderer: MarkdownBlockRenderer) {
        super.init(frame: .zero)
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = context.kind == .post ? 7 : 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        let divider = UIView()
        divider.backgroundColor = .separator
        divider.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        stack.addArrangedSubview(divider)

        let header = UILabel()
        header.text = "FOOTNOTES"
        header.font = context.headingFont(level: 6)
        header.textColor = context.secondaryColor
        stack.addArrangedSubview(header)

        for note in footnotes {
            let m = NSMutableAttributedString(string: "\(note.label). ", attributes: [
                .font: context.smallFont.withTraits(.traitBold), .foregroundColor: context.secondaryColor,
            ])
            m.append(InlineAttributedStringBuilder.build(note.content, context: context))
            m.append(NSAttributedString(string: " ", attributes: [.font: context.smallFont]))
            // U+FE0E (text variation selector) forces text presentation of the
            // return arrow; without it the system falls back to the color emoji
            // ↩️ (which ignores `accentColor`) or, on runtimes lacking the glyph,
            // a missing-glyph box.
            m.append(NSAttributedString(string: "\u{21A9}\u{FE0E}", attributes: [
                .font: context.smallFont,
                .foregroundColor: context.accentColor,
                .link: MarkdownFootnoteLink.url(.toReference(label: note.label)),
            ]))
            stack.addArrangedSubview(renderer.prose(m))
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }
}
