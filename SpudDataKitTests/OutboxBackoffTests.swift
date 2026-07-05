//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudDataKit

struct OutboxBackoffTests {
    @Test
    func delay_doublesAndCaps() {
        #expect(OutboxBackoff.delay(attempts: 1) == 2)
        #expect(OutboxBackoff.delay(attempts: 2) == 4)
        #expect(OutboxBackoff.delay(attempts: 3) == 8)
        #expect(OutboxBackoff.delay(attempts: 0) == 2) // clamped
        #expect(OutboxBackoff.delay(attempts: 20) == 300) // capped
    }
}
