//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import CoreGraphics
import Testing
@testable import Spud

struct InteractiveTransitionGeometryTests {
    // MARK: progress (right-edge drags leftwards -> negative translation)

    @Test
    func progress_zeroAtStart() {
        #expect(abs(InteractiveTransitionGeometry.progress(translationX: 0, viewWidth: 400) - 0) <= 0.0001)
    }

    @Test
    func progress_halfwayAtHalfWidth() {
        #expect(abs(InteractiveTransitionGeometry.progress(translationX: -200, viewWidth: 400) - 0.5) <= 0.0001)
    }

    @Test
    func progress_clampedToOne() {
        #expect(abs(InteractiveTransitionGeometry.progress(translationX: -800, viewWidth: 400) - 1) <= 0.0001)
    }

    @Test
    func progress_clampedToZeroForWrongDirection() {
        #expect(abs(InteractiveTransitionGeometry.progress(translationX: 120, viewWidth: 400) - 0) <= 0.0001)
    }

    @Test
    func progress_zeroWidthIsSafe() {
        #expect(abs(InteractiveTransitionGeometry.progress(translationX: -200, viewWidth: 0) - 0) <= 0.0001)
    }

    // MARK: shouldFinish

    @Test
    func shouldFinish_pastHalfwayFinishes() {
        #expect(InteractiveTransitionGeometry.shouldFinish(progress: 0.6, velocityX: 0))
    }

    @Test
    func shouldFinish_beforeHalfwayCancels() {
        #expect(!(InteractiveTransitionGeometry.shouldFinish(progress: 0.3, velocityX: 0)))
    }

    @Test
    func shouldFinish_exactlyAtThresholdCancels() {
        #expect(!(InteractiveTransitionGeometry.shouldFinish(progress: 0.5, velocityX: 0)))
    }

    @Test
    func shouldFinish_leftwardFlingFinishesEvenIfShort() {
        #expect(InteractiveTransitionGeometry.shouldFinish(progress: 0.1, velocityX: -1200))
    }

    @Test
    func shouldFinish_rightwardFlingCancelsEvenIfLong() {
        #expect(!(InteractiveTransitionGeometry.shouldFinish(progress: 0.9, velocityX: 1200)))
    }

    @Test
    func shouldFinish_exactFlingVelocityIsNotAFling() {
        #expect(!(InteractiveTransitionGeometry.shouldFinish(progress: 0.3, velocityX: -800)))
    }
}
