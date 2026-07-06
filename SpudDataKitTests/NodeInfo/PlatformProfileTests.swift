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
        #expect(p.displayName == "Lemmy")
    }

    @Test
    func nonLemmyIsNotAHomeConnection() {
        #expect(!PlatformProfile.profile(for: .piefed).canBeHomeConnection)
        #expect(!PlatformProfile.profile(for: .mastodon).canBeHomeConnection)
        #expect(!PlatformProfile.profile(for: .other("sublinks")).canBeHomeConnection)
    }

    @Test
    func displayNameForUnknownIsRawName() {
        #expect(PlatformProfile.profile(for: .other("sublinks")).displayName == "sublinks")
    }
}
