//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import CoreGraphics
import XCTest
@testable import Spud

final class InteractiveTransitionGeometryTests: XCTestCase {
    // MARK: progress (right-edge drags leftwards -> negative translation)

    func test_progress_zeroAtStart() {
        XCTAssertEqual(InteractiveTransitionGeometry.progress(translationX: 0, viewWidth: 400), 0, accuracy: 0.0001)
    }

    func test_progress_halfwayAtHalfWidth() {
        XCTAssertEqual(InteractiveTransitionGeometry.progress(translationX: -200, viewWidth: 400), 0.5, accuracy: 0.0001)
    }

    func test_progress_clampedToOne() {
        XCTAssertEqual(InteractiveTransitionGeometry.progress(translationX: -800, viewWidth: 400), 1, accuracy: 0.0001)
    }

    func test_progress_clampedToZeroForWrongDirection() {
        XCTAssertEqual(InteractiveTransitionGeometry.progress(translationX: 120, viewWidth: 400), 0, accuracy: 0.0001)
    }

    func test_progress_zeroWidthIsSafe() {
        XCTAssertEqual(InteractiveTransitionGeometry.progress(translationX: -200, viewWidth: 0), 0, accuracy: 0.0001)
    }

    // MARK: shouldFinish

    func test_shouldFinish_pastHalfwayFinishes() {
        XCTAssertTrue(InteractiveTransitionGeometry.shouldFinish(progress: 0.6, velocityX: 0))
    }

    func test_shouldFinish_beforeHalfwayCancels() {
        XCTAssertFalse(InteractiveTransitionGeometry.shouldFinish(progress: 0.3, velocityX: 0))
    }

    func test_shouldFinish_exactlyAtThresholdCancels() {
        XCTAssertFalse(InteractiveTransitionGeometry.shouldFinish(progress: 0.5, velocityX: 0))
    }

    func test_shouldFinish_leftwardFlingFinishesEvenIfShort() {
        XCTAssertTrue(InteractiveTransitionGeometry.shouldFinish(progress: 0.1, velocityX: -1200))
    }

    func test_shouldFinish_rightwardFlingCancelsEvenIfLong() {
        XCTAssertFalse(InteractiveTransitionGeometry.shouldFinish(progress: 0.9, velocityX: 1200))
    }

    func test_shouldFinish_exactFlingVelocityIsNotAFling() {
        XCTAssertFalse(InteractiveTransitionGeometry.shouldFinish(progress: 0.3, velocityX: -800))
    }
}
