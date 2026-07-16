//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Testing
@testable import SpudDataKit

struct PlatformProfileTests {
    @Test
    func lemmyIsAHomeConnection() {
        let p = PlatformProfile.profile(for: .lemmy, version: "0.19.5")
        #expect(p.speaksLemmyAPI)
        #expect(p.canBeHomeConnection)
        #expect(p.supportsAppRegistration)
        #expect(p.displayName == "Lemmy")
    }

    /// PieFed speaks the Lemmy-compatible `/api/alpha` dialect Spud can drive, so
    /// it can be a home connection (login / signed-out browse) — but in-app
    /// account creation is web-only, so it does NOT support app registration.
    @Test
    func piefedSpeaksLemmyApiButNotRegistration() {
        let p = PlatformProfile.profile(for: .piefed)
        #expect(p.speaksLemmyAPI)
        #expect(p.canBeHomeConnection)
        #expect(!p.supportsAppRegistration)
        #expect(p.displayName == "PieFed")
    }

    @Test
    func nonLemmyIsNotAHomeConnection() {
        #expect(!PlatformProfile.profile(for: .mbin).canBeHomeConnection)
        #expect(!PlatformProfile.profile(for: .mastodon).canBeHomeConnection)
        #expect(!PlatformProfile.profile(for: .other("sublinks")).canBeHomeConnection)
    }

    /// Non-Lemmy, non-PieFed software neither speaks the API nor supports
    /// registration.
    @Test
    func nonLemmyDoesNotSpeakLemmyApiOrRegister() {
        let p = PlatformProfile.profile(for: .mbin)
        #expect(!p.speaksLemmyAPI)
        #expect(!p.supportsAppRegistration)
    }

    @Test
    func displayNameForUnknownIsRawName() {
        #expect(PlatformProfile.profile(for: .other("sublinks")).displayName == "sublinks")
    }
}
