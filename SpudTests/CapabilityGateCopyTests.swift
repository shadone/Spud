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
        let copy = CapabilityGateCopy.copy(for: .inbox, host: "lemmy.world", software: .lemmy)
        #expect(copy.title == "Inbox isn't available yet")
        #expect(copy.message.contains("lemmy.world"))
        #expect(copy.message.contains("newer version of Lemmy"))
        #expect(copy.message.contains("coming in an update"))
    }

    @Test
    func nilHostFallsBackToGenericNoun() {
        let copy = CapabilityGateCopy.copy(for: .hidePosts, host: nil, software: .lemmy)
        #expect(copy.message.contains("This instance"))
    }

    @Test
    func omittedSoftwareDefaultsToLemmyWording() {
        // Call sites that can't (yet) reach the account's resolved software
        // keep exactly today's Lemmy-version framing via the default param.
        let copy = CapabilityGateCopy.copy(for: .inbox, host: "lemmy.world")
        #expect(copy.message.contains("newer version of Lemmy"))
    }

    /// PieFed's gaps (imageUpload, serverUserSettings) are missing dialect
    /// implementations, not a version lag — "runs a newer version of Lemmy"
    /// would be false on PieFed (live-observed against piefed1.lemmy.ddenis.info,
    /// Task 9). The copy must use software-neutral wording instead.
    @Test
    func piefedCopyUsesSoftwareNeutralWording() {
        let copy = CapabilityGateCopy.copy(for: .imageUpload, host: "piefed.example", software: .piefed)
        #expect(copy.message.contains("piefed.example"))
        #expect(!copy.message.contains("Lemmy"))
        #expect(!copy.message.contains("newer version"))
    }

    /// Any other non-Lemmy software falls to the same neutral wording as
    /// PieFed — the Lemmy-version framing is reserved for confirmed Lemmy.
    @Test
    func otherNonLemmySoftwareAlsoUsesSoftwareNeutralWording() {
        let copy = CapabilityGateCopy.copy(for: .serverUserSettings, host: "mystery.example", software: .mbin)
        #expect(!copy.message.contains("Lemmy"))
    }
}
