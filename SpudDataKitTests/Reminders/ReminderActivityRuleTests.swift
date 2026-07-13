//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudDataKit

/// Covers `ReminderActivityRule.shouldFire` (spec §3): the fixed threshold-or-
/// fallback fire rule shared by the activity poll and the "When there are new
/// comments" menu. Pure math, no database/scheduler involved.
struct ReminderActivityRuleTests {
    @Test
    func fiveNewCommentsWithNoElapsedTimeFires() {
        #expect(ReminderActivityRule.shouldFire(newComments: 5, elapsed: 0) == true)
    }

    @Test
    func fourNewCommentsWithNoElapsedTimeDoesNotFire() {
        #expect(ReminderActivityRule.shouldFire(newComments: 4, elapsed: 0) == false)
    }

    @Test
    func oneNewCommentAfterTwentyFourHoursFires() {
        #expect(ReminderActivityRule.shouldFire(newComments: 1, elapsed: 24 * 60 * 60) == true)
    }

    @Test
    func oneNewCommentAfterTwentyThreeHoursDoesNotFire() {
        #expect(ReminderActivityRule.shouldFire(newComments: 1, elapsed: 23 * 60 * 60) == false)
    }

    @Test
    func zeroNewCommentsAfterFortyEightHoursNeverFires() {
        #expect(ReminderActivityRule.shouldFire(newComments: 0, elapsed: 48 * 60 * 60) == false)
    }
}
