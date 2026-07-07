//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SnapshotTesting
import SpudMarkdownKit
import UIKit
import XCTest

final class MarkdownStructuralSnapshotTests: XCTestCase {
    private let sample = """
        | A | B |
        |:--|--:|
        | 1 | 2 |

        ```text
        line one
        line two
        ```

        - item
            - nested

        ::: spoiler Hidden
        secret
        :::

        note.[^1]

        [^1]: a footnote.
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
    func test_structuralPostLight() {
        assertSnapshot(of: render(kind: .post), as: .image(traits: MarkdownSnapshotDeterminism.traits(.light)))
    }

    @MainActor
    func test_structuralPostDark() {
        assertSnapshot(of: render(kind: .post), as: .image(traits: MarkdownSnapshotDeterminism.traits(.dark)))
    }

    @MainActor
    func test_structuralCommentLight() {
        assertSnapshot(of: render(kind: .comment), as: .image(traits: MarkdownSnapshotDeterminism.traits(.light)))
    }

    @MainActor
    func test_structuralCommentDark() {
        assertSnapshot(of: render(kind: .comment), as: .image(traits: MarkdownSnapshotDeterminism.traits(.dark)))
    }
}
