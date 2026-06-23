//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import Spud

final class ScrollToTopUndoTests: XCTestCase {
    private let viewport: CGFloat = 800

    // Arming

    func test_deepScrollToTop_armsUndo_andReturnsPending() {
        var sut = ScrollToTopUndo()
        let response = sut.statusBarTapped(
            currentOffset: CGPoint(x: 0, y: 2400),
            topVisibleServerPostId: 42
        )
        XCTAssertEqual(response, .allowScrollToTop)
        XCTAssertNil(sut.pending, "Not armed until the scroll actually completes")

        let armed = sut.scrolledToTop(viewportHeight: viewport)
        XCTAssertEqual(armed, ScrollToTopUndo.Pending(offset: CGPoint(x: 0, y: 2400), anchorServerPostId: 42))
        XCTAssertEqual(sut.pending, armed)
    }

    func test_shallowScrollToTop_doesNotArm() {
        var sut = ScrollToTopUndo()
        _ = sut.statusBarTapped(currentOffset: CGPoint(x: 0, y: 200), topVisibleServerPostId: 7)
        XCTAssertNil(sut.scrolledToTop(viewportHeight: viewport))
        XCTAssertNil(sut.pending)
    }

    func test_threshold_isInclusiveOfOneViewport() {
        var sut = ScrollToTopUndo()
        _ = sut.statusBarTapped(currentOffset: CGPoint(x: 0, y: viewport), topVisibleServerPostId: 1)
        XCTAssertNotNil(sut.scrolledToTop(viewportHeight: viewport), "offset.y == viewport arms")

        var below = ScrollToTopUndo()
        _ = below.statusBarTapped(currentOffset: CGPoint(x: 0, y: viewport - 1), topVisibleServerPostId: 1)
        XCTAssertNil(below.scrolledToTop(viewportHeight: viewport), "just under one viewport stays silent")
    }

    func test_noVisiblePost_doesNotArm() {
        var sut = ScrollToTopUndo()
        let response = sut.statusBarTapped(currentOffset: CGPoint(x: 0, y: 3000), topVisibleServerPostId: nil)
        XCTAssertEqual(response, .allowScrollToTop)
        XCTAssertNil(sut.scrolledToTop(viewportHeight: viewport))
    }

    // Toggle

    func test_secondTap_whileArmed_returnsUndo_withoutRecapturing() {
        var sut = ScrollToTopUndo()
        _ = sut.statusBarTapped(currentOffset: CGPoint(x: 0, y: 2400), topVisibleServerPostId: 42)
        _ = sut.scrolledToTop(viewportHeight: viewport)

        let response = sut.statusBarTapped(currentOffset: .zero, topVisibleServerPostId: 99)
        XCTAssertEqual(response, .undo)
        XCTAssertEqual(sut.pending?.anchorServerPostId, 42, "toggle keeps the original anchor, not the re-tap")
    }

    // Take undo

    func test_takeUndo_returnsPendingThenClears() {
        var sut = ScrollToTopUndo()
        _ = sut.statusBarTapped(currentOffset: CGPoint(x: 0, y: 2400), topVisibleServerPostId: 42)
        _ = sut.scrolledToTop(viewportHeight: viewport)

        XCTAssertEqual(sut.takeUndo(), ScrollToTopUndo.Pending(offset: CGPoint(x: 0, y: 2400), anchorServerPostId: 42))
        XCTAssertNil(sut.pending)
        XCTAssertNil(sut.takeUndo(), "second take is empty")
    }

    func test_afterUndo_nextTapAllowsScrollToTopAgain() {
        var sut = ScrollToTopUndo()
        _ = sut.statusBarTapped(currentOffset: CGPoint(x: 0, y: 2400), topVisibleServerPostId: 42)
        _ = sut.scrolledToTop(viewportHeight: viewport)
        _ = sut.takeUndo()

        XCTAssertEqual(
            sut.statusBarTapped(currentOffset: CGPoint(x: 0, y: 1500), topVisibleServerPostId: 5),
            .allowScrollToTop
        )
    }

    // Invalidate

    func test_invalidate_clearsArmedUndo() {
        var sut = ScrollToTopUndo()
        _ = sut.statusBarTapped(currentOffset: CGPoint(x: 0, y: 2400), topVisibleServerPostId: 42)
        _ = sut.scrolledToTop(viewportHeight: viewport)

        sut.invalidate()
        XCTAssertNil(sut.pending)
        XCTAssertEqual(
            sut.statusBarTapped(currentOffset: CGPoint(x: 0, y: 2400), topVisibleServerPostId: 42),
            .allowScrollToTop,
            "after invalidate a tap is a fresh scroll-to-top, not a toggle"
        )
    }

    func test_invalidate_clearsPendingCandidateBeforePromotion() {
        var sut = ScrollToTopUndo()
        _ = sut.statusBarTapped(currentOffset: CGPoint(x: 0, y: 2400), topVisibleServerPostId: 42)
        sut.invalidate()
        XCTAssertNil(sut.scrolledToTop(viewportHeight: viewport), "an invalidated candidate cannot promote")
    }
}
