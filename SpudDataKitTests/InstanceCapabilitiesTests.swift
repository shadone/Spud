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

    @Test(arguments: ["1.0.0-alpha.18", "2.0.0"])
    func lemmy1NativelySupportsEveryCapability(versionString: String) {
        // The Phase-1 gating that withheld seven capabilities on Lemmy 1.0 (while
        // Spud spoke only v3 and the 1.0 server's v3 shim lacked the endpoints)
        // has been retired: Spud now speaks native v4, so every capability is
        // available on a Lemmy 1.0+ instance.
        let caps = InstanceCapabilities.capabilities(
            software: .lemmy,
            version: LemmyVersion(parsing: versionString)
        )
        for capability in InstanceCapability.allCases {
            #expect(caps.can(capability), "expected \(capability) available on Lemmy \(versionString) (gating retired)")
        }
    }

    @Test
    func explicitlyGatedSetWithholdsOnlyThoseCapabilities() {
        // The version-derivation table gates nothing today, but the MECHANISM is
        // kept intact for non-Lemmy software and future capabilities: a directly
        // constructed gated set still withholds exactly its members and fails open
        // for the rest.
        let caps = InstanceCapabilities(unavailable: [.inbox, .privateMessages])
        #expect(!caps.can(.inbox))
        #expect(!caps.can(.privateMessages))
        #expect(caps.can(.personProfiles))
        #expect(caps.can(.imageUpload))
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
        // PieFed's own version numbers (e.g. "1.2.0") are not on the Lemmy
        // scale, so the derivation must not mis-apply the Lemmy shim table to
        // them — `version` is ignored entirely for non-Lemmy software (see
        // `piefedWithholdsOnlyImageUploadAndServerUserSettings` for the actual
        // PieFed-specific gaps this table now encodes).
        let caps = InstanceCapabilities.capabilities(
            software: .piefed,
            version: LemmyVersion(parsing: "1.2.0")
        )
        #expect(caps.can(.inbox))
    }

    @Test
    func piefedWithholdsOnlyImageUploadAndServerUserSettings() {
        // Confirmed live against piefed1.lemmy.ddenis.info + the local LemmyKit
        // `feat/piefed-dialect` checkout (Phase 2, Task 8): the dialect has no
        // multipart image-upload implementation, and no `saveUserSettings`
        // implementation (unverified wire shape) — every other capability,
        // including the ones LemmyKit DOES implement for PieFed (person
        // profiles, inbox, private messages, hide-posts, mark-posts-read),
        // stays available.
        let caps = InstanceCapabilities.capabilities(software: .piefed, version: nil)
        #expect(!caps.can(.imageUpload))
        #expect(!caps.can(.serverUserSettings))
        for capability in InstanceCapability.allCases where capability != .imageUpload && capability != .serverUserSettings {
            #expect(caps.can(capability), "expected \(capability) available on PieFed")
        }
    }

    @Test
    func platformProfileExposesCapabilities() {
        // Lemmy 1.0 is no longer gated now that Spud speaks native v4, so both a
        // 1.0 and a 0.19 profile report the inbox as available.
        let profile = PlatformProfile.profile(for: .lemmy, version: "1.0.0")
        #expect(profile.capabilities.can(.inbox))
        let old = PlatformProfile.profile(for: .lemmy, version: "0.19.11")
        #expect(old.capabilities.can(.inbox))
    }
}
