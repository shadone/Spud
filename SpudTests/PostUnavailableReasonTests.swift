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
        canModerate: Bool = false, isOwnPost: Bool = false,
        resolved: Bool = true
    ) -> PostUnavailableReason? {
        PostUnavailableReason.forHeader(
            isRemoved: removed, isDeleted: deleted, isUnavailable: unavailable,
            canModerate: canModerate, isOwnPost: isOwnPost,
            moderationCapabilityResolved: resolved
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

    @Test
    func unresolvedDefersRemoved() {
        #expect(reason(removed: true, resolved: false) == nil)
    }

    @Test
    func unresolvedDefersDeleted() {
        #expect(reason(deleted: true, resolved: false) == nil)
    }

    @Test
    func unresolvedStillShowsUnavailable() {
        // couldnt_find_post is privilege-independent — never deferred.
        #expect(reason(unavailable: true, resolved: false) == .unavailable)
    }
}
