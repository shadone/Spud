//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Testing
@testable import Spud

struct CompactCountTests {
    @Test
    func string_matchesExistingCompactStyle() {
        #expect(CompactCount.string(312) == "312")
        #expect(CompactCount.string(1000) == "1K")
        #expect(CompactCount.string(1234) == "1.2K")
        #expect(CompactCount.string(32000) == "32K")
        #expect(CompactCount.string(120_000) == "120K")
        #expect(CompactCount.string(1_200_000) == "1.2M")
    }
}
