//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import Spud

final class PersonFormatterTests: XCTestCase {
    func test_banStatus_notBanned_isNil() {
        XCTAssertNil(PersonFormatter.banStatus(isBanned: false, banExpires: nil))
        XCTAssertNil(PersonFormatter.banStatus(isBanned: false, banExpires: Date(timeIntervalSince1970: 1_800_000_000)))
    }

    func test_banStatus_permanent_whenBannedWithNoExpiry() {
        XCTAssertEqual(PersonFormatter.banStatus(isBanned: true, banExpires: nil), "Banned")
    }

    func test_banStatus_temporary_includesExpiry() {
        let status = PersonFormatter.banStatus(
            isBanned: true,
            banExpires: Date(timeIntervalSince1970: 1_800_000_000)
        )
        // The exact date string is locale/timezone-dependent; assert the shape.
        XCTAssertEqual(status?.hasPrefix("Banned · until "), true)
    }
}
