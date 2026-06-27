//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import Spud

struct ForwardStackReducerTests {
    // Stand-ins for view controllers — only identity matters to the reducer.
    private let a = NSObject()
    private let b = NSObject()
    private let c = NSObject()

    @Test
    func singlePop_prependsRemoved() {
        let result = ForwardStackReducer.reduce(forwardStack: [], lastStack: [a, b], newStack: [a], animated: true)
        #expect(result == [b])
    }

    @Test
    func secondPop_prependsNearestAheadFirst() {
        // Already backed out of b; now backing out of a.
        let result = ForwardStackReducer.reduce(forwardStack: [b], lastStack: [a], newStack: [], animated: true)
        #expect(result == [a, b])
    }

    @Test
    func multiLevelPop_prependsInOrder() {
        let result = ForwardStackReducer.reduce(forwardStack: [], lastStack: [a, b, c], newStack: [a], animated: true)
        #expect(result == [b, c])
    }

    @Test
    func restorePush_consumesFirst() {
        let result = ForwardStackReducer.reduce(forwardStack: [b, c], lastStack: [a], newStack: [a, b], animated: true)
        #expect(result == [c])
    }

    @Test
    func feedSwitcher_popThenRestorePush_roundTripsToEmpty() {
        // Start on [switcher(a), postList(b)] with nothing pending.
        // 1) Swipe back: postList is popped, becoming forward-restorable.
        let afterPop = ForwardStackReducer.reduce(
            forwardStack: [], lastStack: [a, b], newStack: [a], animated: true
        )
        #expect(afterPop == [b])

        // 2) Pick a feed (or forward-swipe): the SAME postList is re-pushed and
        //    consumed, leaving a clean forward stack.
        let afterRestore = ForwardStackReducer.reduce(
            forwardStack: afterPop, lastStack: [a], newStack: [a, b], animated: true
        )
        #expect(afterRestore == [])
    }

    @Test
    func newPush_clearsStack() {
        let result = ForwardStackReducer.reduce(forwardStack: [b], lastStack: [a], newStack: [a, c], animated: true)
        #expect(result == [])
    }

    @Test
    func nonAnimatedChange_isIgnored() {
        // Split-view column handoff via setViewControllers(animated: false).
        let result = ForwardStackReducer.reduce(forwardStack: [b], lastStack: [a], newStack: [a, c], animated: false)
        #expect(result == [b])
    }

    @Test
    func noNetChange_keepsStack() {
        // A cancelled interactive restore nets to no stack change.
        let result = ForwardStackReducer.reduce(forwardStack: [b], lastStack: [a], newStack: [a], animated: true)
        #expect(result == [b])
    }

    @Test
    func reshuffle_clearsStack() {
        let result = ForwardStackReducer.reduce(forwardStack: [b], lastStack: [a, b], newStack: [c], animated: true)
        #expect(result == [])
    }

    @Test
    func emptyToEmpty_staysEmpty() {
        let result = ForwardStackReducer.reduce(forwardStack: [], lastStack: [a], newStack: [a], animated: true)
        #expect(result == [])
    }
}
