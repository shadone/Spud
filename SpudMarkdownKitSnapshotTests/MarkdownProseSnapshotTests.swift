//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SnapshotTesting
import SpudMarkdownKit
import UIKit
import XCTest

final class MarkdownProseSnapshotTests: XCTestCase {
    private let sample = """
        Valve **finally** shipped it, with ~~three~~ two edges. Ping @alice@lemmy.world in !linux@lemmy.world.

        # Heading One
        ## Heading Two

        - first **item**
        - second `item`

        1. step one
        2. step two

        > a quoted line

        H~2~O and E=mc^2^. A [link](https://example.com).

        ---
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
    func test_postLight() {
        assertSnapshot(of: render(kind: .post), as: .image(traits: UITraitCollection(userInterfaceStyle: .light)))
    }

    @MainActor
    func test_postDark() {
        assertSnapshot(of: render(kind: .post), as: .image(traits: UITraitCollection(userInterfaceStyle: .dark)))
    }

    @MainActor
    func test_commentLight() {
        assertSnapshot(of: render(kind: .comment), as: .image(traits: UITraitCollection(userInterfaceStyle: .light)))
    }

    @MainActor
    func test_commentDark() {
        assertSnapshot(of: render(kind: .comment), as: .image(traits: UITraitCollection(userInterfaceStyle: .dark)))
    }
}
