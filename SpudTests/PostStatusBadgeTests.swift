//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Testing
import UIKit
@testable import Spud

struct PostStatusBadgeTests {
    @Test
    func unavailableShowsNeutralBadge() {
        let badges = PostStatusBadge.badges(
            isRemoved: false, isDeleted: false, isUnavailable: true,
            isLocked: false, isFeatured: false
        )
        #expect(badges.count == 1)
        #expect(badges[0].symbolName == "exclamationmark.octagon")
        #expect(badges[0].color == .secondaryLabel)
    }

    @Test
    func removedTakesPriorityOverUnavailable() {
        let badges = PostStatusBadge.badges(
            isRemoved: true, isDeleted: false, isUnavailable: true,
            isLocked: false, isFeatured: false
        )
        #expect(badges.count == 1)
        #expect(badges[0].symbolName == "trash.slash.fill")
        #expect(badges[0].color == .systemRed)
    }

    @Test
    func availablePostHasNoStatusBadge() {
        let badges = PostStatusBadge.badges(
            isRemoved: false, isDeleted: false, isUnavailable: false,
            isLocked: false, isFeatured: false
        )
        #expect(badges.isEmpty)
    }

    @Test
    func deletedTakesPriorityOverUnavailable() {
        let badges = PostStatusBadge.badges(
            isRemoved: false, isDeleted: true, isUnavailable: true,
            isLocked: false, isFeatured: false
        )
        #expect(badges.count == 1)
        #expect(badges[0].symbolName == "trash.fill")
        #expect(badges[0].color == .systemRed)
    }
}
