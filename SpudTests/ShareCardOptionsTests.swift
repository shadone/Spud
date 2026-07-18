//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import Spud

struct ShareCardOptionsTests {
    @Test
    func defaults_matchTheDesignSpec() {
        let options = ShareCardOptions()

        #expect(options.appearance == .light)
        #expect(options.showCommunityAndCreator == true)
        #expect(options.showStats == true)
        #expect(options.showMedia == true)
        #expect(options.bodyTreatment == .truncate)
        #expect(options.redactIdentities == false)
        #expect(options.chainDepth == 2)
        #expect(options.includePostInChain == true)
        #expect(options.canvas == .native)
        #expect(options.showViaSpudMark == true)
        #expect(options.nsfwRevealed == false)
    }

    @Test
    func chainDepth_isClampedToZeroToEight() {
        #expect(ShareCardOptions(chainDepth: -3).chainDepth == 0)
        #expect(ShareCardOptions(chainDepth: 42).chainDepth == 8)
        #expect(ShareCardOptions(chainDepth: 5).chainDepth == 5)
    }

    @Test
    func codable_roundTripsEveryFieldExceptNsfwRevealed() throws {
        let original = ShareCardOptions(
            appearance: .dark,
            showCommunityAndCreator: false,
            showStats: false,
            showMedia: false,
            bodyTreatment: .titleOnly,
            redactIdentities: true,
            chainDepth: 4,
            includePostInChain: false,
            canvas: .story,
            showViaSpudMark: false,
            nsfwRevealed: true
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ShareCardOptions.self, from: data)

        #expect(decoded.appearance == original.appearance)
        #expect(decoded.showCommunityAndCreator == original.showCommunityAndCreator)
        #expect(decoded.showStats == original.showStats)
        #expect(decoded.showMedia == original.showMedia)
        #expect(decoded.bodyTreatment == original.bodyTreatment)
        #expect(decoded.redactIdentities == original.redactIdentities)
        #expect(decoded.chainDepth == original.chainDepth)
        #expect(decoded.includePostInChain == original.includePostInChain)
        #expect(decoded.canvas == original.canvas)
        #expect(decoded.showViaSpudMark == original.showViaSpudMark)

        // The guardrail under test: nsfwRevealed is never persisted, so a
        // decode always reads back false regardless of what was encoded.
        #expect(original.nsfwRevealed == true)
        #expect(decoded.nsfwRevealed == false)
    }

    @Test
    func codable_decodingLegacyJSONWithoutNsfwRevealedKey_defaultsToFalse() throws {
        // Forward-compatibility: nsfwRevealed was never in CodingKeys, so a
        // stored JSON blob from before this field existed still decodes.
        let json = """
            {
                "appearance": "light",
                "showCommunityAndCreator": true,
                "showStats": true,
                "showMedia": true,
                "bodyTreatment": "truncate",
                "redactIdentities": false,
                "chainDepth": 2,
                "includePostInChain": true,
                "canvas": "native",
                "showViaSpudMark": true
            }
            """
        let decoded = try JSONDecoder().decode(ShareCardOptions.self, from: Data(json.utf8))
        #expect(decoded.nsfwRevealed == false)
        #expect(decoded.chainDepth == 2)
    }
}
