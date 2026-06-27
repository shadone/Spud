//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import Spud

struct SeenDwellTrackerTests {
    private let threshold: TimeInterval = 0.5
    private let t0 = Date(timeIntervalSince1970: 1000)

    @Test
    func appearThenDisappearPastThresholdIsSeen() {
        var tracker = SeenDwellTracker(threshold: threshold)
        tracker.didAppear(serverPostId: 1, at: t0)
        let seen = tracker.didDisappear(serverPostId: 1, at: t0.addingTimeInterval(0.6))
        #expect(seen == 1)
    }

    @Test
    func disappearBeforeThresholdIsNotSeen() {
        var tracker = SeenDwellTracker(threshold: threshold)
        tracker.didAppear(serverPostId: 1, at: t0)
        let seen = tracker.didDisappear(serverPostId: 1, at: t0.addingTimeInterval(0.3))
        #expect(seen == nil)
    }

    @Test
    func flushReturnsPostsStillOnScreenPastThreshold() {
        var tracker = SeenDwellTracker(threshold: threshold)
        tracker.didAppear(serverPostId: 1, at: t0)
        tracker.didAppear(serverPostId: 2, at: t0.addingTimeInterval(0.4))
        // At t0+0.6: post 1 has dwelled 0.6 (seen), post 2 only 0.2 (not yet).
        let seen = tracker.flushSeen(at: t0.addingTimeInterval(0.6))
        #expect(seen == [1])
        // Post 1 is not reported twice on a later flush.
        let seenAgain = tracker.flushSeen(at: t0.addingTimeInterval(0.7))
        #expect(seenAgain == [])
    }

    @Test
    func disappearWithoutAppearIsIgnored() {
        var tracker = SeenDwellTracker(threshold: threshold)
        #expect(tracker.didDisappear(serverPostId: 99, at: t0) == nil)
    }
}
