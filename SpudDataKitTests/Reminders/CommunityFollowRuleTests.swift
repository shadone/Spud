//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudDataKit

/// Covers `CommunityFollowRule.shouldFire`: the fixed fire rule for a
/// community "new posts" follow. Pure math, no database/scheduler involved -
/// mirrors `ReminderActivityRuleTests`.
struct CommunityFollowRuleTests {
    @Test
    func firesOnOneNewPost() {
        #expect(CommunityFollowRule.shouldFire(newPosts: 1))
    }

    @Test
    func firesOnManyNewPosts() {
        #expect(CommunityFollowRule.shouldFire(newPosts: 12))
    }

    @Test
    func neverFiresOnZero() {
        #expect(!CommunityFollowRule.shouldFire(newPosts: 0))
    }

    @Test
    func pollIntervalMatchesActivityThrottle() {
        #expect(CommunityFollowRule.pollInterval == ReminderActivityRule.pollInterval)
    }
}
