//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SwiftUI
import Testing
@testable import Spud

/// Covers the offline-download progress ring's Reduce Motion gate: with the
/// setting on the arc must snap to each new fraction (no tween), while still
/// updating — the ring keeps conveying progress, it just stops sweeping.
struct OfflineDownloadProgressRingTests {
    @Test
    func reduceMotionRemovesTheTrimAnimation() {
        #expect(OfflineDownloadProgressRing.trimAnimation(reduceMotion: true) == nil)
    }

    @Test
    func motionAllowedKeepsTheEaseInOutTween() {
        #expect(
            OfflineDownloadProgressRing.trimAnimation(reduceMotion: false)
                == .easeInOut(duration: 0.25)
        )
    }
}
