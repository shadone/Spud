//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import Testing
@testable import Spud

/// Pins the shared 5-state title/symbol vocabulary that both `CommunityHeaderView`
/// and `SearchCommunityCell` render from `CommunitySubscribeButtonLabel`. If this
/// helper's mapping ever drifts, both surfaces drift together — which is the
/// point (this DRY consolidation is the fix for Search having its own,
/// independently-lossy label logic).
struct CommunitySubscribeButtonLabelTests {
    @Test
    func title_notSubscribed_isSubscribe() {
        #expect(CommunitySubscribeButtonLabel.title(for: .notSubscribed) == "Subscribe")
    }

    @Test
    func title_subscribed_isSubscribed() {
        #expect(CommunitySubscribeButtonLabel.title(for: .subscribed) == "Subscribed")
    }

    @Test
    func title_pending_isPending() {
        #expect(CommunitySubscribeButtonLabel.title(for: .pending) == "Pending")
    }

    @Test
    func title_approvalRequired_isRequested() {
        #expect(CommunitySubscribeButtonLabel.title(for: .approvalRequired) == "Requested")
    }

    /// `.denied` still offers to re-subscribe, so its primary title matches
    /// `.notSubscribed` — callers (e.g. `CommunityHeaderView`) layer a "Request
    /// declined" subtitle / VoiceOver label on top rather than this helper
    /// changing the title itself.
    @Test
    func title_denied_isSubscribe() {
        #expect(CommunitySubscribeButtonLabel.title(for: .denied) == "Subscribe")
    }

    @Test
    func symbol_matchesEachState() {
        #expect(CommunitySubscribeButtonLabel.symbol(for: .notSubscribed) == "plus")
        #expect(CommunitySubscribeButtonLabel.symbol(for: .denied) == "plus")
        #expect(CommunitySubscribeButtonLabel.symbol(for: .subscribed) == "checkmark")
        #expect(CommunitySubscribeButtonLabel.symbol(for: .pending) == "clock")
        #expect(CommunitySubscribeButtonLabel.symbol(for: .approvalRequired) == "hourglass")
    }
}
