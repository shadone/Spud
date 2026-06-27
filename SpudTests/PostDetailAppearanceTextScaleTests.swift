//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Testing
@testable import Spud

/// The Display settings "Text Size" slider writes one value
/// (`PreferencesService.postTextScale`). Post detail must read that same value
/// as the post list — not a separate dead key — so the slider scales both.
@MainActor
struct PostDetailAppearanceTextScaleTests {
    @Test
    func postDetailTextScale_followsSliderAndMatchesPostList() {
        let preferencesService = PreferencesService()
        let originalScale = preferencesService.postTextScale
        defer { preferencesService.postTextScale = originalScale }

        let appearance = AppearanceService(preferencesService: preferencesService)

        preferencesService.postTextScale = -2
        #expect(
            appearance.postDetail.textSizeAdjustment == -2,
            "post detail should follow the Text Size slider"
        )
        #expect(
            appearance.postDetail.textSizeAdjustment == appearance.postList.textSizeAdjustment,
            "post detail and post list should share one text-scale source"
        )

        // Writing through the post-detail appearance updates the shared value too.
        appearance.postDetail.textSizeAdjustment = 3
        #expect(preferencesService.postTextScale == 3)
    }
}
