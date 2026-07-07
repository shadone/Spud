//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Testing
@testable import SpudDataKit

struct InstanceCapabilitiesTests {
    @Test
    func lemmy019HasEverything() {
        let caps = InstanceCapabilities.capabilities(
            software: .lemmy,
            version: LemmyVersion(parsing: "0.19.11")
        )
        for capability in InstanceCapability.allCases {
            #expect(caps.can(capability))
        }
    }

    @Test
    func lemmy1ViaV3ShimLosesEveryGatedCapability() {
        let caps = InstanceCapabilities.capabilities(
            software: .lemmy,
            version: LemmyVersion(parsing: "1.0.0-alpha.18")
        )
        for capability in InstanceCapability.allCases {
            #expect(!caps.can(capability), "expected \(capability) gated on Lemmy 1.0 via the v3 shim")
        }
    }

    @Test
    func unknownVersionFailsOpen() {
        let caps = InstanceCapabilities.capabilities(software: .lemmy, version: nil)
        for capability in InstanceCapability.allCases {
            #expect(caps.can(capability))
        }
    }

    @Test
    func nonLemmySoftwareFailsOpen() {
        // Non-Lemmy software can't be a home connection (PlatformRouter blocks
        // it), so capabilities are moot there — but the derivation must not
        // mis-apply the Lemmy shim table to e.g. PieFed version numbers.
        let caps = InstanceCapabilities.capabilities(
            software: .piefed,
            version: LemmyVersion(parsing: "1.2.0")
        )
        #expect(caps.can(.inbox))
    }

    @Test
    func platformProfileExposesCapabilities() {
        let profile = PlatformProfile.profile(for: .lemmy, version: "1.0.0")
        #expect(!profile.capabilities.can(.inbox))
        let old = PlatformProfile.profile(for: .lemmy, version: "0.19.11")
        #expect(old.capabilities.can(.inbox))
    }
}
