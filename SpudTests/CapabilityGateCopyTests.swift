//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import Testing
@testable import Spud

struct CapabilityGateCopyTests {
    @Test
    func inboxCopyNamesHostAndPromisesSupport() {
        let copy = CapabilityGateCopy.copy(for: .inbox, host: "lemmy.world")
        #expect(copy.title == "Inbox isn't available yet")
        #expect(copy.message.contains("lemmy.world"))
        #expect(copy.message.contains("newer version of Lemmy"))
        #expect(copy.message.contains("coming in an update"))
    }

    @Test
    func nilHostFallsBackToGenericNoun() {
        let copy = CapabilityGateCopy.copy(for: .hidePosts, host: nil)
        #expect(copy.message.contains("This instance"))
    }
}
