//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import Spud

final class ForwardStackReducerTests: XCTestCase {
    // Stand-ins for view controllers — only identity matters to the reducer.
    private let a = NSObject()
    private let b = NSObject()
    private let c = NSObject()

    func test_singlePop_prependsRemoved() {
        let result = ForwardStackReducer.reduce(forwardStack: [], lastStack: [a, b], newStack: [a], animated: true)
        XCTAssertEqual(result, [b])
    }

    func test_secondPop_prependsNearestAheadFirst() {
        // Already backed out of b; now backing out of a.
        let result = ForwardStackReducer.reduce(forwardStack: [b], lastStack: [a], newStack: [], animated: true)
        XCTAssertEqual(result, [a, b])
    }

    func test_multiLevelPop_prependsInOrder() {
        let result = ForwardStackReducer.reduce(forwardStack: [], lastStack: [a, b, c], newStack: [a], animated: true)
        XCTAssertEqual(result, [b, c])
    }

    func test_restorePush_consumesFirst() {
        let result = ForwardStackReducer.reduce(forwardStack: [b, c], lastStack: [a], newStack: [a, b], animated: true)
        XCTAssertEqual(result, [c])
    }

    func test_feedSwitcher_popThenRestorePush_roundTripsToEmpty() {
        // Start on [switcher(a), postList(b)] with nothing pending.
        // 1) Swipe back: postList is popped, becoming forward-restorable.
        let afterPop = ForwardStackReducer.reduce(
            forwardStack: [], lastStack: [a, b], newStack: [a], animated: true
        )
        XCTAssertEqual(afterPop, [b])

        // 2) Pick a feed (or forward-swipe): the SAME postList is re-pushed and
        //    consumed, leaving a clean forward stack.
        let afterRestore = ForwardStackReducer.reduce(
            forwardStack: afterPop, lastStack: [a], newStack: [a, b], animated: true
        )
        XCTAssertEqual(afterRestore, [])
    }

    func test_newPush_clearsStack() {
        let result = ForwardStackReducer.reduce(forwardStack: [b], lastStack: [a], newStack: [a, c], animated: true)
        XCTAssertEqual(result, [])
    }

    func test_nonAnimatedChange_isIgnored() {
        // Split-view column handoff via setViewControllers(animated: false).
        let result = ForwardStackReducer.reduce(forwardStack: [b], lastStack: [a], newStack: [a, c], animated: false)
        XCTAssertEqual(result, [b])
    }

    func test_noNetChange_keepsStack() {
        // A cancelled interactive restore nets to no stack change.
        let result = ForwardStackReducer.reduce(forwardStack: [b], lastStack: [a], newStack: [a], animated: true)
        XCTAssertEqual(result, [b])
    }

    func test_reshuffle_clearsStack() {
        let result = ForwardStackReducer.reduce(forwardStack: [b], lastStack: [a, b], newStack: [c], animated: true)
        XCTAssertEqual(result, [])
    }

    func test_emptyToEmpty_staysEmpty() {
        let result = ForwardStackReducer.reduce(forwardStack: [], lastStack: [a], newStack: [a], animated: true)
        XCTAssertEqual(result, [])
    }
}
