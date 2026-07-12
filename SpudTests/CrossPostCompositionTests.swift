//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import Spud

/// Covers `crossPostBody`, the pure helper that seeds a cross-post's
/// attribution body. Mirrors lemmy-ui's `crossPostBody` (`post-listing.tsx`):
/// a body-bearing original gets a quoted attribution, a link/no-body original
/// gets nil (title + url alone establish the cross-post).
struct CrossPostCompositionTests {
    private let apId = "https://lemmy.example/post/123"

    @Test
    func originalHasBody_quotesEveryLineWithAttributionPrefix() {
        let body = crossPostBody(originalApId: apId, originalBody: "line one\nline two")

        #expect(body == "cross-posted from: \(apId)\n\n> line one\n> line two")
    }

    @Test
    func originalHasSingleLineBody_quotesIt() {
        let body = crossPostBody(originalApId: apId, originalBody: "just one line")

        #expect(body == "cross-posted from: \(apId)\n\n> just one line")
    }

    @Test
    func originalBodyIsNil_returnsNil() {
        #expect(crossPostBody(originalApId: apId, originalBody: nil) == nil)
    }

    @Test
    func originalBodyIsBlank_returnsNil() {
        #expect(crossPostBody(originalApId: apId, originalBody: "   \n  ") == nil)
    }

    @Test
    func originalBodyIsEmptyString_returnsNil() {
        #expect(crossPostBody(originalApId: apId, originalBody: "") == nil)
    }
}
