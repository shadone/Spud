//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Testing
import UIKit
@testable import SpudMarkdownKit

@MainActor
struct MarkdownContextTests {
    @Test
    func postBodyLargerThanComment() {
        let post = MarkdownContext(kind: .post)
        let comment = MarkdownContext(kind: .comment)
        #expect(post.bodyFont.pointSize > comment.bodyFont.pointSize)
    }

    @Test
    func headingWeights() {
        let ctx = MarkdownContext(kind: .post)
        #expect(ctx.headingFont(level: 1).fontDescriptor.symbolicTraits.contains(.traitBold) == true)
        #expect(ctx.headingFont(level: 1).pointSize > ctx.headingFont(level: 3).pointSize)
    }

    @Test
    func textScaleIncreasesBody() {
        let base = MarkdownContext(kind: .post, textScale: 0)
        let bigger = MarkdownContext(kind: .post, textScale: 4)
        #expect(bigger.bodyFont.pointSize > base.bodyFont.pointSize)
    }

    @Test
    func compactDensityShrinksBody() {
        let comfortable = MarkdownContext(kind: .post, density: .comfortable)
        let compact = MarkdownContext(kind: .post, density: .compact)
        #expect(compact.bodyFont.pointSize < comfortable.bodyFont.pointSize)
    }

    @Test
    func interBlockGap() {
        #expect(
            MarkdownContext(kind: .post).interBlockGap >
                MarkdownContext(kind: .comment).interBlockGap
        )
    }

    /// With no overrides the inline-code chip keeps the default colors — the
    /// zero-change guarantee for posts and comments.
    @Test
    func inlineCodeColorsDefaultWithoutOverride() {
        let ctx = MarkdownContext(kind: .comment)
        #expect(ctx.inlineCodeForeground == MarkdownColors.inlineCodeForeground)
        #expect(ctx.inlineCodeBackground == .secondarySystemFill)
    }

    /// The inline-code overrides win when set (e.g. white code on the outgoing
    /// DM bubble's teal fill), independently of the body/link overrides.
    @Test
    func inlineCodeColorsHonorOverrides() {
        let background = UIColor.white.withAlphaComponent(0.2)
        let ctx = MarkdownContext(
            kind: .comment,
            inlineCodeForegroundOverride: .white,
            inlineCodeBackgroundOverride: background
        )
        #expect(ctx.inlineCodeForeground == .white)
        #expect(ctx.inlineCodeBackground == background)
    }
}
