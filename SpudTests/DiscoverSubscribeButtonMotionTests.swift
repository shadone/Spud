//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SwiftUI
import Testing
@testable import Spud

/// Covers Discover's Subscribe pill's Reduce Motion gate: with the setting on
/// the pill must cut straight to its new state rather than cross-fading and
/// resizing between Subscribe, the spinner, and Subscribed.
struct DiscoverSubscribeButtonMotionTests {
    @Test
    func reduceMotionRemovesTheStateAnimation() {
        #expect(SubscribeButton.stateAnimation(reduceMotion: true) == nil)
    }

    @Test
    func motionAllowedKeepsTheEaseInOutTween() {
        #expect(
            SubscribeButton.stateAnimation(reduceMotion: false)
                == .easeInOut(duration: 0.15)
        )
    }
}
