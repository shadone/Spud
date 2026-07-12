//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import Testing
@testable import SpudDataKit

/// Pins the neutral `FollowState` -> persisted `CommunitySubscribedState`
/// mapping and the derived `isSubscribed`, including the v4-only
/// `.approvalRequired` / `.denied` states that were previously collapsed.
struct CommunitySubscribedStateTests {
    /// Every `FollowState` maps 1:1 onto a `CommunitySubscribedState` — the
    /// v4-only `.approvalRequired` / `.denied` are preserved distinctly rather
    /// than folded into `.pending` / `.notSubscribed`.
    @Test
    func followStateMapsOneToOne() {
        #expect(CommunitySubscribedState(followState: .accepted) == .subscribed)
        #expect(CommunitySubscribedState(followState: .pending) == .pending)
        #expect(CommunitySubscribedState(followState: .approvalRequired) == .approvalRequired)
        #expect(CommunitySubscribedState(followState: .denied) == .denied)
        #expect(CommunitySubscribedState(followState: .notFollowing) == .notSubscribed)
    }

    /// `isSubscribed` (drives sidebar membership + the subscribe toggle): an
    /// active follow OR an in-flight request counts; a denied request does not.
    @Test
    func isSubscribedCountsInFlightRequestsButNotDenied() {
        #expect(CommunitySubscribedState.subscribed.isSubscribed)
        #expect(CommunitySubscribedState.pending.isSubscribed)
        #expect(CommunitySubscribedState.approvalRequired.isSubscribed)
        #expect(!CommunitySubscribedState.notSubscribed.isSubscribed)
        #expect(!CommunitySubscribedState.denied.isSubscribed)
    }

    /// The persisted raw values are the stable on-disk contract for the
    /// `community.subscribedState` text column; they must not drift.
    @Test
    func rawValuesAreStable() {
        #expect(CommunitySubscribedState.subscribed.rawValue == "Subscribed")
        #expect(CommunitySubscribedState.notSubscribed.rawValue == "NotSubscribed")
        #expect(CommunitySubscribedState.pending.rawValue == "Pending")
        #expect(CommunitySubscribedState.approvalRequired.rawValue == "ApprovalRequired")
        #expect(CommunitySubscribedState.denied.rawValue == "Denied")
    }
}
