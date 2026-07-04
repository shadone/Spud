//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Testing
@testable import Spud

struct PostUnavailableReasonTests {
    private func reason(
        removed: Bool = false, deleted: Bool = false, unavailable: Bool = false,
        canModerate: Bool = false, isOwnPost: Bool = false
    ) -> PostUnavailableReason? {
        PostUnavailableReason.forHeader(
            isRemoved: removed, isDeleted: deleted, isUnavailable: unavailable,
            canModerate: canModerate, isOwnPost: isOwnPost
        )
    }

    @Test
    func availablePostShowsNothing() {
        #expect(reason() == nil)
    }

    @Test
    func unavailableShowsUnavailable() {
        #expect(reason(unavailable: true) == .unavailable)
    }

    @Test
    func removedNonModShowsRemoved() {
        #expect(reason(removed: true) == .removed)
    }

    @Test
    func removedModKeepsContent() {
        #expect(reason(removed: true, canModerate: true) == nil)
    }

    @Test
    func ownDeletedKeepsContent() {
        #expect(reason(deleted: true, isOwnPost: true) == nil)
    }

    @Test
    func otherDeletedShowsDeleted() {
        #expect(reason(deleted: true) == .deleted)
    }

    @Test
    func deletedModKeepsContent() {
        #expect(reason(deleted: true, canModerate: true) == nil)
    }
}
