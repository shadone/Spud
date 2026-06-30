//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit
import Testing

struct PersonFormatterTests {
    @Test
    func banStatus_notBanned_isNil() {
        #expect(PersonFormatter.banStatus(isBanned: false, banExpires: nil) == nil)
        #expect(PersonFormatter.banStatus(isBanned: false, banExpires: Date(timeIntervalSince1970: 1_800_000_000)) == nil)
    }

    @Test
    func banStatus_permanent_whenBannedWithNoExpiry() {
        #expect(PersonFormatter.banStatus(isBanned: true, banExpires: nil) == "Banned")
    }

    @Test
    func banStatus_temporary_includesExpiry() {
        let status = PersonFormatter.banStatus(
            isBanned: true,
            banExpires: Date(timeIntervalSince1970: 1_800_000_000)
        )
        // The exact date string is locale/timezone-dependent; assert the shape.
        #expect(status?.hasPrefix("Banned · until ") == true)
    }
}
