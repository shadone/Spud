//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import XCTest
@testable import SpudUtilKit

final class URLSanitizerMigrationTests: XCTestCase {
    func test_legacyOn_andNotYetMigrated_seedsTwitterFrontEnd() throws {
        let migrated = try XCTUnwrap(
            URLSanitizerConfig.migratingFromLegacyXcancel(legacyEnabled: true, alreadyMigrated: false)
        )
        XCTAssertTrue(migrated.redirectToFrontEnds)
        let twitter = migrated.setting(for: .twitter)
        XCTAssertTrue(twitter.isEnabled)
        XCTAssertEqual(twitter.host, "xcancel.com")
        // Other services remain off.
        XCTAssertFalse(migrated.setting(for: .youtube).isEnabled)
    }

    func test_legacyOff_returnsNil() {
        XCTAssertNil(URLSanitizerConfig.migratingFromLegacyXcancel(legacyEnabled: false, alreadyMigrated: false))
    }

    func test_alreadyMigrated_returnsNil() {
        XCTAssertNil(URLSanitizerConfig.migratingFromLegacyXcancel(legacyEnabled: true, alreadyMigrated: true))
    }
}
