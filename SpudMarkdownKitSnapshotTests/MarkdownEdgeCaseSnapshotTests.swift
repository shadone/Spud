//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SnapshotTesting
import SpudMarkdownKit
import UIKit
import XCTest

final class MarkdownEdgeCaseSnapshotTests: XCTestCase {
    private let sample = """
        Link to [the docs](https://example.com), mention @ada@lemmy.world, community !rust@lemmy.world.

        Literal markup stays text: a <b>not bold</b> tag and :notarealemoji: shortcode.

        > level one
        > > level two
        > > > level three

        | Col A | Col B | Col C | Col D | Col E | Col F |
        |:--|--:|:-:|:--|--:|:--|
        | alpha | beta | gamma | delta | epsilon | zeta |
        | 1 | 2 | 3 | 4 | 5 | 6 |

        ::: spoiler
        hidden body with no title
        :::
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
    func test_edgesPostLight() {
        assertSnapshot(of: render(kind: .post), as: .image(traits: MarkdownSnapshotDeterminism.traits(.light)))
    }

    @MainActor
    func test_edgesPostDark() {
        assertSnapshot(of: render(kind: .post), as: .image(traits: MarkdownSnapshotDeterminism.traits(.dark)))
    }

    @MainActor
    func test_edgesCommentLight() {
        assertSnapshot(of: render(kind: .comment), as: .image(traits: MarkdownSnapshotDeterminism.traits(.light)))
    }

    @MainActor
    func test_edgesCommentDark() {
        assertSnapshot(of: render(kind: .comment), as: .image(traits: MarkdownSnapshotDeterminism.traits(.dark)))
    }
}
