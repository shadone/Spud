//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SnapshotTesting
import SpudMarkdownKit
import UIKit
import XCTest

final class MarkdownLongURLSnapshotTests: XCTestCase {
    private let sample = """
        Check out this resource before continuing:

        https://example.com/a/very/long/path/segment/that/keeps/going/and/going/until/it/overflows/the/column.html

        That link has the full details.
        """

    @MainActor
    private func render(kind: MarkdownContextKind, width: CGFloat = 360) -> UIView {
        let view = MarkdownBodyView(context: MarkdownContext(kind: kind))
        view.setBlocks(MarkdownParser.parse(sample))
        view.translatesAutoresizingMaskIntoConstraints = false
        let container = UIView()
        container.backgroundColor = .systemBackground
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            view.widthAnchor.constraint(equalToConstant: width - 32),
        ])
        container.widthAnchor.constraint(equalToConstant: width).isActive = true
        container.layoutIfNeeded()
        container.frame = CGRect(
            x: 0,
            y: 0,
            width: width,
            height: container.systemLayoutSizeFitting(
                CGSize(width: width, height: UIView.layoutFittingCompressedSize.height)
            ).height
        )
        return container
    }

    @MainActor
    func test_longURLPost() {
        assertSnapshot(of: render(kind: .post), as: .image(traits: MarkdownSnapshotDeterminism.traits(.light)))
    }

    @MainActor
    func test_longURLComment() {
        assertSnapshot(of: render(kind: .comment), as: .image(traits: MarkdownSnapshotDeterminism.traits(.light)))
    }
}
