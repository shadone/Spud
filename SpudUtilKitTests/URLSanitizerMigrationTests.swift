//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudUtilKit

struct URLSanitizerMigrationTests {
    @Test
    func legacyOn_andNotYetMigrated_seedsTwitterFrontEnd() throws {
        let migrated = try #require(
            URLSanitizerConfig.migratingFromLegacyXcancel(legacyEnabled: true, alreadyMigrated: false)
        )
        #expect(migrated.redirectToFrontEnds)
        let twitter = migrated.setting(for: .twitter)
        #expect(twitter.isEnabled)
        #expect(twitter.host == "xcancel.com")
        // Other services remain off.
        #expect(!(migrated.setting(for: .youtube).isEnabled))
    }

    @Test
    func legacyOff_returnsNil() {
        #expect(URLSanitizerConfig.migratingFromLegacyXcancel(legacyEnabled: false, alreadyMigrated: false) == nil)
    }

    @Test
    func alreadyMigrated_returnsNil() {
        #expect(URLSanitizerConfig.migratingFromLegacyXcancel(legacyEnabled: true, alreadyMigrated: true) == nil)
    }
}
