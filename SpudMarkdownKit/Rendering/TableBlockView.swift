//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// A markdown table: a horizontally-scrolling grid with a tinted header row,
/// per-column alignment, and hairline separators. In a comment context the grid
/// is given a minimum width so it scrolls under the thread rail rather than
/// crushing columns.
final class TableBlockView: UIView {
    init(table: MarkdownTable, context: MarkdownContext) {
        super.init(frame: .zero)
        layer.cornerRadius = context.kind == .post ? 10 : 8
        layer.borderWidth = 0.5
        layer.borderColor = UIColor.separator.cgColor
        // CGColor is a snapshot — re-resolve it on light/dark change.
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: TableBlockView, _: UITraitCollection) in
            view.layer.borderColor = UIColor.separator.cgColor
        }
        clipsToBounds = true

        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)

        let grid = UIStackView()
        grid.axis = .vertical
        grid.translatesAutoresizingMaskIntoConstraints = false

        let allRows = [table.head] + table.rows
        for (r, cells) in allRows.enumerated() {
            let isHeader = r == 0
            let row = UIStackView()
            row.axis = .horizontal
            row.alignment = .fill
            if isHeader { row.backgroundColor = .tertiarySystemFill }
            for (c, cell) in cells.enumerated() {
                let label = ProseBlockView()
                let attributed = NSMutableAttributedString(
                    attributedString: InlineAttributedStringBuilder.build(cell, context: context)
                )
                let style = NSMutableParagraphStyle()
                style.alignment = nsAlignment(table.alignments[safe: c] ?? .left)
                attributed.addAttributes(
                    [
                        .paragraphStyle: style,
                        .font: isHeader ? context.bodyFont.withTraits(.traitBold) : context.bodyFont,
                        .foregroundColor: isHeader ? context.labelColor : context.secondaryColor,
                    ],
                    range: NSRange(location: 0, length: attributed.length)
                )
                label.attributedText = attributed
                label.isSelectable = false
                let cellPad: CGFloat = context.kind == .post ? 10 : 7
                label.textContainerInset = UIEdgeInsets(top: cellPad * 0.7, left: cellPad, bottom: cellPad * 0.7, right: cellPad)
                label.widthAnchor.constraint(greaterThanOrEqualToConstant: 64).isActive = true
                row.addArrangedSubview(label)
                if c < cells.count - 1 { row.addArrangedSubview(hairline(vertical: true)) }
            }
            grid.addArrangedSubview(row)
            if r < allRows.count - 1 { grid.addArrangedSubview(hairline(vertical: false)) }
        }

        scroll.addSubview(grid)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            grid.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            grid.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            grid.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            scroll.heightAnchor.constraint(equalTo: grid.heightAnchor),
        ])
        if context.kind == .comment {
            grid.widthAnchor.constraint(greaterThanOrEqualToConstant: 360).isActive = true
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    private func hairline(vertical: Bool) -> UIView {
        let line = UIView()
        line.backgroundColor = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        (vertical ? line.widthAnchor : line.heightAnchor).constraint(equalToConstant: 0.5).isActive = true
        return line
    }

    private func nsAlignment(_ a: MarkdownTable.Alignment) -> NSTextAlignment {
        switch a {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
