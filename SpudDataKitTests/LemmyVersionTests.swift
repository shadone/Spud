//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Testing
@testable import SpudDataKit

struct LemmyVersionTests {
    @Test(arguments: [
        ("0.19.11", 0, 19, 11),
        ("1.0.0", 1, 0, 0),
        ("1.0.0-alpha.18", 1, 0, 0),
        ("1.2.3-rc.1", 1, 2, 3),
        ("0.19", 0, 19, 0),
        ("1", 1, 0, 0),
    ])
    func parsesVersionStrings(input: String, major: Int, minor: Int, patch: Int) {
        let version = LemmyVersion(parsing: input)
        #expect(version?.major == major)
        #expect(version?.minor == minor)
        #expect(version?.patch == patch)
    }

    @Test(arguments: ["", "unknown", "v1.0.0", "one.two", "-alpha", "."])
    func rejectsUnparseableStrings(input: String) {
        #expect(LemmyVersion(parsing: input) == nil)
    }
}
