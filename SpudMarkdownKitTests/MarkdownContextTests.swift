//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit
import XCTest
@testable import SpudMarkdownKit

@MainActor
final class MarkdownContextTests: XCTestCase {
    func test_postBodyLargerThanComment() {
        let post = MarkdownContext(kind: .post)
        let comment = MarkdownContext(kind: .comment)
        XCTAssertGreaterThan(post.bodyFont.pointSize, comment.bodyFont.pointSize)
    }

    func test_headingWeights() {
        let ctx = MarkdownContext(kind: .post)
        XCTAssertEqual(ctx.headingFont(level: 1).fontDescriptor.symbolicTraits.contains(.traitBold), true)
        XCTAssertGreaterThan(ctx.headingFont(level: 1).pointSize, ctx.headingFont(level: 3).pointSize)
    }

    func test_textScaleIncreasesBody() {
        let base = MarkdownContext(kind: .post, textScale: 0)
        let bigger = MarkdownContext(kind: .post, textScale: 4)
        XCTAssertGreaterThan(bigger.bodyFont.pointSize, base.bodyFont.pointSize)
    }

    func test_compactDensityShrinksBody() {
        let comfortable = MarkdownContext(kind: .post, density: .comfortable)
        let compact = MarkdownContext(kind: .post, density: .compact)
        XCTAssertLessThan(compact.bodyFont.pointSize, comfortable.bodyFont.pointSize)
    }

    func test_interBlockGap() {
        XCTAssertGreaterThan(
            MarkdownContext(kind: .post).interBlockGap,
            MarkdownContext(kind: .comment).interBlockGap
        )
    }
}
