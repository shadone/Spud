//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit
import XCTest
@testable import SpudMarkdownKit

@MainActor
final class MarkdownBodyHitTestTests: XCTestCase {
    /// Builds a laid-out body sized to its fitting size at a fixed width, so the
    /// rendered block frames are tight enough to hit-test against.
    private func laidOutBody(_ blocks: [MarkdownBlock]) -> MarkdownBodyView {
        let body = MarkdownBodyView(context: MarkdownContext(kind: .comment))
        body.setBlocks(blocks)
        let width: CGFloat = 320
        body.frame = CGRect(x: 0, y: 0, width: width, height: 1000)
        body.setNeedsLayout()
        body.layoutIfNeeded()
        let fitting = body.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        body.frame = CGRect(origin: .zero, size: fitting)
        body.setNeedsLayout()
        body.layoutIfNeeded()
        return body
    }

    private func center(of view: UIView) -> CGPoint {
        CGPoint(x: view.bounds.midX, y: view.bounds.midY)
    }

    /// Proves the regression is fixed: a plain paragraph with no links must NOT
    /// be treated as link-like, so the collapse-tap still collapses.
    func test_plainParagraph_doesNotHandleTap() {
        let blocks = MarkdownParser.parse("Just some plain text with no links at all.")
        let body = laidOutBody(blocks)
        XCTAssertFalse(body.handlesTap(at: center(of: body)))
    }

    /// A media tile is tappable across its whole frame.
    func test_imageBlock_handlesTapAnywhere() {
        let blocks = MarkdownParser.parse("![alt](https://example.com/x.png)")
        let body = laidOutBody(blocks)
        XCTAssertTrue(body.handlesTap(at: center(of: body)))
    }

    /// A paragraph that is entirely a link: a tap landing on the link's own
    /// selection rect inside the prose view must defer to the body. The point is
    /// derived from the link's actual rect rather than the prose view's geometric
    /// center, because a short link does not span the full prose width (the prose
    /// view is laid out full-width, so its center can sit past the text).
    func test_linkParagraph_handlesTapOnLink() {
        let blocks = MarkdownParser.parse("[click here](https://example.com)")
        let body = laidOutBody(blocks)

        guard let prose = firstProseBlockView(in: body) else {
            return XCTFail("expected a ProseBlockView for a link-only paragraph")
        }
        guard let linkRect = firstLinkRect(in: prose) else {
            return XCTFail("expected a link selection rect in the link-only paragraph")
        }
        let pointInProse = CGPoint(x: linkRect.midX, y: linkRect.midY)
        let pointInBody = prose.convert(pointInProse, to: body)
        XCTAssertTrue(body.handlesTap(at: pointInBody))
    }

    /// A collapsed spoiler installs its own tap recognizer on the disclosure
    /// header to toggle open/closed. While collapsed the body stack is hidden, so
    /// the spoiler block's bounds equal just the header — a tap at the body's
    /// center lands on the header and must defer to the spoiler, not collapse the
    /// comment thread.
    func test_spoilerHeader_handlesTap() {
        let blocks = MarkdownParser.parse("::: spoiler Secret\nhidden body text\n:::")
        let body = laidOutBody(blocks)
        XCTAssertTrue(body.handlesTap(at: center(of: body)))
    }

    /// Returns the selection rect of the first `.link` range in `prose`, in the
    /// prose view's coordinate space. Mirrors `ProseBlockView.rects(for:)`.
    private func firstLinkRect(in prose: ProseBlockView) -> CGRect? {
        guard let attributed = prose.attributedText, attributed.length > 0 else { return nil }
        var result: CGRect?
        attributed.enumerateAttribute(
            .link,
            in: NSRange(location: 0, length: attributed.length)
        ) { value, range, stop in
            guard value != nil else { return }
            guard
                let start = prose.position(from: prose.beginningOfDocument, offset: range.location),
                let end = prose.position(from: start, offset: range.length),
                let textRange = prose.textRange(from: start, to: end)
            else { return }
            let rects = prose.selectionRects(for: textRange)
                .map(\.rect)
                .filter { $0.width > 0 && $0.height > 0 }
            if let first = rects.first {
                result = first
                stop.pointee = true
            }
        }
        return result
    }

    private func firstProseBlockView(in view: UIView) -> ProseBlockView? {
        for subview in view.subviews {
            if let prose = subview as? ProseBlockView { return prose }
            if let found = firstProseBlockView(in: subview) { return found }
        }
        return nil
    }
}
