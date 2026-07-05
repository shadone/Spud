//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Testing
@testable import Spud

struct FeedFailurePresentationTests {
    /// The core invariant: with posts already on screen, a load failure keeps
    /// them and toasts — it must never install the transparent full error surface
    /// on top of live content (the see-through overlap bug).
    @Test
    func keepsContentWhenPostsAreDisplayed() {
        #expect(FeedFailurePresentation.decide(hasContent: true) == .keepContentWithToast)
    }

    /// With an empty list (e.g. an initial-load failure) the full error surface is
    /// shown — there is nothing behind the transparent overlay.
    @Test
    func showsFullSurfaceWhenListIsEmpty() {
        #expect(FeedFailurePresentation.decide(hasContent: false) == .fullErrorSurface)
    }
}
