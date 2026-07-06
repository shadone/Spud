//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Testing
@testable import SpudUtilKit

struct CountFormatterTests {
    @Test
    func compactBoundaries() {
        #expect(CountFormatter.string(0) == "0")
        #expect(CountFormatter.string(999) == "999")
        #expect(CountFormatter.string(1000) == "1K")
        #expect(CountFormatter.string(1234) == "1.2K")
        #expect(CountFormatter.string(5000) == "5K")
        #expect(CountFormatter.string(32000) == "32K")
        #expect(CountFormatter.string(100_000) == "100K")
        #expect(CountFormatter.string(312_000) == "312K")
        #expect(CountFormatter.string(1_000_000) == "1M")
        #expect(CountFormatter.string(1_250_000) == "1.2M")
    }

    @Test
    func negativesAndSmallRenderVerbatim() {
        #expect(CountFormatter.string(-5) == "-5")
        #expect(CountFormatter.string(-5000) == "-5000")
    }
}
