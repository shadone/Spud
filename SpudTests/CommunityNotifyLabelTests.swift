//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Testing
@testable import Spud

/// Pins the shared "Notify About New Posts" copy + symbols rendered by every
/// surface (community overflow, Search context menu). If this helper's
/// wording or symbol choice ever drifts, every surface drifts together —
/// that's the point of centralizing it here rather than hardcoding the
/// strings at each call site.
struct CommunityNotifyLabelTests {
    @Test
    func title_isNonEmpty() {
        #expect(!CommunityNotifyLabel.title.isEmpty)
    }

    @Test
    func symbol_notNotifying_isBellBadge() {
        #expect(CommunityNotifyLabel.symbol(isNotifying: false) == "bell.badge")
    }

    @Test
    func symbol_notifying_isBellBadgeFill() {
        #expect(CommunityNotifyLabel.symbol(isNotifying: true) == "bell.badge.fill")
    }

    /// The on/off symbols must differ - the whole point of a state-driven
    /// checkmark/badge is that it's visually distinguishable per state.
    @Test
    func symbol_differsByState() {
        #expect(CommunityNotifyLabel.symbol(isNotifying: true) != CommunityNotifyLabel.symbol(isNotifying: false))
    }

    /// Neither symbol collides with `bell`/`bell.slash`/`bell.fill` - those
    /// belong to Mute/Unmute (and the Remind Me submenu), which can appear in
    /// the same menus as this action.
    @Test
    func symbols_doNotCollideWithMuteOrRemindMeSymbols() {
        let reserved: Set = ["bell", "bell.slash", "bell.fill"]
        #expect(!reserved.contains(CommunityNotifyLabel.symbol(isNotifying: true)))
        #expect(!reserved.contains(CommunityNotifyLabel.symbol(isNotifying: false)))
    }

    @Test
    func toastOn_isNonEmpty() {
        #expect(!CommunityNotifyLabel.toastOn.isEmpty)
    }

    @Test
    func toastOff_isNonEmpty() {
        #expect(!CommunityNotifyLabel.toastOff.isEmpty)
    }

    /// The two toasts must differ - a shared string would leave the user
    /// unable to tell from the toast alone whether the follow was set or
    /// removed.
    @Test
    func toasts_differ() {
        #expect(CommunityNotifyLabel.toastOn != CommunityNotifyLabel.toastOff)
    }
}
