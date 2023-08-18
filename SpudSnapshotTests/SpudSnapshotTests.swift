//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Down
import SnapshotTesting
import UIKit
import XCTest
@testable import Spud

final class SpudSnapshotTests: XCTestCase {
    let vc = MarkdownViewController()

    func styler(textSizeAdjustment: CGFloat = 0) -> Styler {
        let configuration = PostDetailAppearance.bodyStylerConfiguration(for: textSizeAdjustment)
        return DownStyler(configuration: configuration)
    }

    private func markdown(_ string: String, styler: Styler) -> NSAttributedString {
        let attributedString = try? Down(markdownString: string)
            .toAttributedString(styler: styler)
        XCTAssertNotNil(attributedString)
        return attributedString!
    }

    func testSimple() throws {
        let text = "hello **bold** and *italic* world"
        vc.attributedText = markdown(text, styler: styler())
        assertSnapshot(matching: vc, as: .image(traits: .init(userInterfaceStyle: .light)))
    }

    func testMlemMarkdownTest() throws {
        // https://lemmy.ml/post/3462852
        let text = "**bold**\n\n*italics*\n\n# header\n\n## header 2\n\n~~strikethrough~~\n\n>quote\n\n- list\n- list\n\n1. ordered list\n2. ordered list\n\ninline `code` inline\n\nabc~subscript~\n\nabc^superscript^\n\n::: spoiler spoiler\na bunch of spoilers here\n:::\n\n---\n\n```\ncode block\ncode block\n```"
        vc.attributedText = markdown(text, styler: styler())
        assertSnapshot(matching: vc, as: .image(traits: .init(userInterfaceStyle: .light)))
    }
}
