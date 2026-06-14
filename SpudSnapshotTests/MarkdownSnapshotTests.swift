//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Down
import SnapshotTesting
import UIKit
import XCTest
@testable import Spud

/// Renders markdown bodies (the `LinkLabel` inside `MarkdownViewController`) to
/// images so the styler output can be reviewed and regressions caught.
///
/// The view is pinned to a fixed content width (the feed/cell width 390) and its
/// height is derived by Auto Layout, then snapshot with `.image(size:traits:)` at
/// a fixed display scale. This makes the references device-independent — they
/// record and verify identically on any simulator, rather than being locked to
/// the recording device's screen size like a bare `.image(traits:)` would be.
@MainActor
final class MarkdownSnapshotTests: XCTestCase {
    /// Content width to render the markdown body at — matches the feed/cell width.
    private let width: CGFloat = 390

    private func traits(_ style: UIUserInterfaceStyle) -> UITraitCollection {
        UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: style),
            UITraitCollection(displayScale: 2),
        ])
    }

    private func styler(textSizeAdjustment: CGFloat = 0) -> Styler {
        let configuration = PostDetailAppearance.bodyStylerConfiguration(for: textSizeAdjustment)
        return DownStyler(configuration: configuration)
    }

    private func markdown(_ string: String, styler: Styler) -> NSAttributedString {
        Down(markdownString: string)
            .toAttributedString(styler: styler)
    }

    /// Builds the view controller, lays its view out at the fixed width, and
    /// returns the height that fits the rendered markdown.
    private func makeView(markdown attributedText: NSAttributedString) -> (UIView, CGFloat) {
        let vc = MarkdownViewController()
        vc.attributedText = attributedText

        let view = vc.view!
        view.frame = CGRect(x: 0, y: 0, width: width, height: 2000)
        view.layoutIfNeeded()

        let height = view.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height

        return (view, height)
    }

    func testSimple() {
        let text = "hello **bold** and *italic* world and [this](https://example.com) link"
        let (view, height) = makeView(markdown: markdown(text, styler: styler()))
        assertSnapshot(
            matching: view,
            as: .image(size: CGSize(width: width, height: height), traits: traits(.light))
        )
    }

    func testMlemMarkdownTest() {
        // https://lemmy.ml/post/3462852
        let text = "**bold**\n\n*italics*\n\n# header\n\n## header 2\n\n~~strikethrough~~\n\n>quote\n\n- list\n- list\n\n1. ordered list\n2. ordered list\n\ninline `code` inline\n\nabc~subscript~\n\nabc^superscript^\n\n::: spoiler spoiler\na bunch of spoilers here\n:::\n\n---\n\n```\ncode block\ncode block\n```"
        let (view, height) = makeView(markdown: markdown(text, styler: styler()))
        assertSnapshot(
            matching: view,
            as: .image(size: CGSize(width: width, height: height), traits: traits(.light))
        )
    }
}
