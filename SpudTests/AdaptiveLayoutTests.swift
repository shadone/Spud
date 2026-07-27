//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
import UIKit
@testable import Spud

struct AdaptiveLayoutTests {
    /// The banner downsample target must not depend on anything a window
    /// resize can change. It previously derived from `UIScreen.main.bounds`,
    /// which reports the screen rather than the scene — wrong under iPad split
    /// view and iPhone Mirroring, where an app's space is not the full screen.
    @Test
    func bannerDownsampleWidth_isScreenIndependent() {
        #expect(AdaptiveLayout.bannerDownsampleWidth() == AdaptiveLayout.contentMaxWidth)
    }

    @Test
    func bannerDownsampleWidth_honoursAnExplicitCap() {
        #expect(AdaptiveLayout.bannerDownsampleWidth(cap: 320) == 320)
    }
}
