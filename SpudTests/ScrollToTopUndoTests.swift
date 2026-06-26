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

    // Recovery sequence: a manual scroll between jumps keeps the deepest target

    /// The reported bug: deep jump, ignore the toast, manually scroll partway back
    /// down, then jump to the top again. The second jump must still offer to undo
    /// to the original deep position, not the shallower spot you stopped at.
    func test_reJumpAfterPartialRecovery_keepsDeepestOriginalTarget() {
        var sut = ScrollToTopUndo()

        _ = sut.statusBarTapped(currentOffset: CGPoint(x: 0, y: 2400), topVisibleServerPostId: 42)
        XCTAssertEqual(sut.scrolledToTop(viewportHeight: viewport)?.offset.y, 2400)

        // Ignore the toast and manually scroll back partway to y=1200.
        sut.userDidScroll()
        XCTAssertNil(sut.pending, "a manual scroll disarms the toggle")

        // A second status-bar jump from the shallower 1200 re-arms to the deeper
        // original 2400, not 1200.
        XCTAssertEqual(
            sut.statusBarTapped(currentOffset: CGPoint(x: 0, y: 1200), topVisibleServerPostId: 7),
            .allowScrollToTop
        )
        XCTAssertEqual(
            sut.scrolledToTop(viewportHeight: viewport),
            ScrollToTopUndo.Pending(offset: CGPoint(x: 0, y: 2400), anchorServerPostId: 42),
            "re-jump after partial recovery should undo to the deepest original position"
        )
    }

    /// Even a shallow re-jump (under one viewport, which would not arm on its own)
    /// still offers the remembered deep target.
    func test_shallowReJumpAfterRecovery_stillOffersDeepTarget() {
        var sut = ScrollToTopUndo()
        _ = sut.statusBarTapped(currentOffset: CGPoint(x: 0, y: 2400), topVisibleServerPostId: 42)
        _ = sut.scrolledToTop(viewportHeight: viewport)

        sut.userDidScroll()
        _ = sut.statusBarTapped(currentOffset: CGPoint(x: 0, y: 100), topVisibleServerPostId: 7)
        XCTAssertEqual(
            sut.scrolledToTop(viewportHeight: viewport)?.offset.y, 2400,
            "a shallow re-jump still recovers the deep target"
        )
    }

    /// If the recovery scroll overshoots deeper than the original, the new deeper
    /// position becomes the target.
    func test_reJumpFromDeeperPosition_usesNewDeeperTarget() {
        var sut = ScrollToTopUndo()
        _ = sut.statusBarTapped(currentOffset: CGPoint(x: 0, y: 2400), topVisibleServerPostId: 42)
        _ = sut.scrolledToTop(viewportHeight: viewport)

        sut.userDidScroll()
        _ = sut.statusBarTapped(currentOffset: CGPoint(x: 0, y: 5000), topVisibleServerPostId: 99)
        XCTAssertEqual(
            sut.scrolledToTop(viewportHeight: viewport),
            ScrollToTopUndo.Pending(offset: CGPoint(x: 0, y: 5000), anchorServerPostId: 99),
            "a deeper re-jump returns to the deeper position"
        )
    }

    func test_userDidScroll_disarmsToggleButKeepsDeepMemory() {
        var sut = ScrollToTopUndo()
        _ = sut.statusBarTapped(currentOffset: CGPoint(x: 0, y: 2400), topVisibleServerPostId: 42)
        _ = sut.scrolledToTop(viewportHeight: viewport)

        sut.userDidScroll()
        // The toggle is disarmed: a tap is a fresh scroll-to-top, not an undo.
        XCTAssertEqual(
            sut.statusBarTapped(currentOffset: CGPoint(x: 0, y: 1200), topVisibleServerPostId: 7),
            .allowScrollToTop
        )
    }

    /// Consuming the undo ends the recovery sequence: the deep memory is cleared,
    /// so the next jump starts fresh from its own position.
    func test_takeUndo_clearsDeepMemory() {
        var sut = ScrollToTopUndo()
        _ = sut.statusBarTapped(currentOffset: CGPoint(x: 0, y: 2400), topVisibleServerPostId: 42)
        _ = sut.scrolledToTop(viewportHeight: viewport)
        _ = sut.takeUndo()

        _ = sut.statusBarTapped(currentOffset: CGPoint(x: 0, y: 1500), topVisibleServerPostId: 5)
        XCTAssertEqual(
            sut.scrolledToTop(viewportHeight: viewport),
            ScrollToTopUndo.Pending(offset: CGPoint(x: 0, y: 1500), anchorServerPostId: 5),
            "after an undo the next jump uses its own position, not the old deep one"
        )
    }

    /// A feed change is a hard reset: the deep memory belongs to the prior feed.
    func test_invalidate_clearsDeepMemory() {
        var sut = ScrollToTopUndo()
        _ = sut.statusBarTapped(currentOffset: CGPoint(x: 0, y: 2400), topVisibleServerPostId: 42)
        _ = sut.scrolledToTop(viewportHeight: viewport)

        sut.invalidate()
        _ = sut.statusBarTapped(currentOffset: CGPoint(x: 0, y: 100), topVisibleServerPostId: 7)
        XCTAssertNil(
            sut.scrolledToTop(viewportHeight: viewport),
            "after a feed change the deep memory is gone, so a shallow jump stays silent"
        )
    }
}
