//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Testing
@testable import SpudDataKit

struct ExplorerInstanceHealthTests {
    @Test
    func uptime_levels() {
        #expect(ExplorerInstanceHealth.uptime(99.7).level == .good)
        #expect(ExplorerInstanceHealth.uptime(97).level == .ok)
        #expect(ExplorerInstanceHealth.uptime(80).level == .bad)
        #expect(ExplorerInstanceHealth.uptime(nil).level == .unknown)
        #expect(ExplorerInstanceHealth.uptime(nil).short == "—")
        #expect(ExplorerInstanceHealth.uptime(99.7).short == "99.7%")
        #expect(ExplorerInstanceHealth.uptime(99).short == "99%")
    }

    @Test
    func version_freshness() {
        #expect(ExplorerInstanceHealth.version("0.19.5", latest: "0.19.5").level == .good)
        #expect(ExplorerInstanceHealth.version("0.19.4", latest: "0.19.5").level == .ok)
        #expect(ExplorerInstanceHealth.version("0.18.1", latest: "0.19.5").level == .bad)
        #expect(ExplorerInstanceHealth.version(nil, latest: "0.19.5").level == .unknown)
        // A newer-than-latest build is still "good", not penalised.
        #expect(ExplorerInstanceHealth.version("0.20.0", latest: "0.19.5").level == .good)
    }

    @Test
    func registration() {
        #expect(ExplorerInstanceHealth.registration(.open).level == .good)
        #expect(ExplorerInstanceHealth.registration(.open).canCreateAccount)
        #expect(ExplorerInstanceHealth.registration(.requireApplication).level == .ok)
        #expect(ExplorerInstanceHealth.registration(.requireApplication).canCreateAccount)
        #expect(ExplorerInstanceHealth.registration(.closed).level == .bad)
        #expect(!(ExplorerInstanceHealth.registration(.closed).canCreateAccount))
        #expect(!(ExplorerInstanceHealth.registration(.unknown).canCreateAccount))
    }

    @Test
    func trust() {
        #expect(ExplorerInstanceHealth.trust(score100: 96, suspicious: false).level == .good)
        #expect(ExplorerInstanceHealth.trust(score100: 60, suspicious: false).level == .ok)
        #expect(ExplorerInstanceHealth.trust(score100: 20, suspicious: false).level == .bad)
        #expect(ExplorerInstanceHealth.trust(score100: nil, suspicious: false).label == "Unrated")
        // Suspicious overrides a high score.
        #expect(ExplorerInstanceHealth.trust(score100: 96, suspicious: true).level == .bad)
        #expect(ExplorerInstanceHealth.trust(score100: 96, suspicious: true).label == "Low trust")
    }
}
