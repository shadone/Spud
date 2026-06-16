//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import XCTest
@testable import Spud

final class SeenDwellTrackerTests: XCTestCase {
    private let threshold: TimeInterval = 0.5
    private let t0 = Date(timeIntervalSince1970: 1000)

    func testAppearThenDisappearPastThresholdIsSeen() {
        var tracker = SeenDwellTracker(threshold: threshold)
        tracker.didAppear(serverPostId: 1, at: t0)
        let seen = tracker.didDisappear(serverPostId: 1, at: t0.addingTimeInterval(0.6))
        XCTAssertEqual(seen, 1)
    }

    func testDisappearBeforeThresholdIsNotSeen() {
        var tracker = SeenDwellTracker(threshold: threshold)
        tracker.didAppear(serverPostId: 1, at: t0)
        let seen = tracker.didDisappear(serverPostId: 1, at: t0.addingTimeInterval(0.3))
        XCTAssertNil(seen)
    }

    func testFlushReturnsPostsStillOnScreenPastThreshold() {
        var tracker = SeenDwellTracker(threshold: threshold)
        tracker.didAppear(serverPostId: 1, at: t0)
        tracker.didAppear(serverPostId: 2, at: t0.addingTimeInterval(0.4))
        // At t0+0.6: post 1 has dwelled 0.6 (seen), post 2 only 0.2 (not yet).
        let seen = tracker.flushSeen(at: t0.addingTimeInterval(0.6))
        XCTAssertEqual(seen, [1])
        // Post 1 is not reported twice on a later flush.
        let seenAgain = tracker.flushSeen(at: t0.addingTimeInterval(0.7))
        XCTAssertEqual(seenAgain, [])
    }

    func testDisappearWithoutAppearIsIgnored() {
        var tracker = SeenDwellTracker(threshold: threshold)
        XCTAssertNil(tracker.didDisappear(serverPostId: 99, at: t0))
    }
}
