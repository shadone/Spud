//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudDataKit

struct LoopsHashidTests {
    @Test
    func decodesGoldenVector() {
        #expect(LoopsHashid.decode("gLbKEGRkoA") == "301511283332957732")
    }

    @Test
    func decodesSingleCharacterBoundaries() {
        #expect(LoopsHashid.decode("0") == "0")
        #expect(LoopsHashid.decode("_") == "63")
    }

    @Test
    func rejectsEmpty() {
        #expect(LoopsHashid.decode("") == nil)
    }

    @Test
    func rejectsTooLong() {
        // 11 characters — one over the 10-character cap.
        #expect(LoopsHashid.decode("aaaaaaaaaaa") == nil)
    }

    @Test
    func rejectsOutOfAlphabet() {
        #expect(LoopsHashid.decode("bad*code") == nil)
        #expect(LoopsHashid.decode("has space") == nil)
    }
}
