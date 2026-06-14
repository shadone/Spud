//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import SpudDataKit

final class ExplorerInstanceHealthTests: XCTestCase {
    func test_uptime_levels() {
        XCTAssertEqual(ExplorerInstanceHealth.uptime(99.7).level, .good)
        XCTAssertEqual(ExplorerInstanceHealth.uptime(97).level, .ok)
        XCTAssertEqual(ExplorerInstanceHealth.uptime(80).level, .bad)
        XCTAssertEqual(ExplorerInstanceHealth.uptime(nil).level, .unknown)
        XCTAssertEqual(ExplorerInstanceHealth.uptime(nil).short, "—")
        XCTAssertEqual(ExplorerInstanceHealth.uptime(99.7).short, "99.7%")
        XCTAssertEqual(ExplorerInstanceHealth.uptime(99).short, "99%")
    }

    func test_version_freshness() {
        XCTAssertEqual(ExplorerInstanceHealth.version("0.19.5", latest: "0.19.5").level, .good)
        XCTAssertEqual(ExplorerInstanceHealth.version("0.19.4", latest: "0.19.5").level, .ok)
        XCTAssertEqual(ExplorerInstanceHealth.version("0.18.1", latest: "0.19.5").level, .bad)
        XCTAssertEqual(ExplorerInstanceHealth.version(nil, latest: "0.19.5").level, .unknown)
        // A newer-than-latest build is still "good", not penalised.
        XCTAssertEqual(ExplorerInstanceHealth.version("0.20.0", latest: "0.19.5").level, .good)
    }

    func test_registration() {
        XCTAssertEqual(ExplorerInstanceHealth.registration(.open).level, .good)
        XCTAssertTrue(ExplorerInstanceHealth.registration(.open).canCreateAccount)
        XCTAssertEqual(ExplorerInstanceHealth.registration(.requireApplication).level, .ok)
        XCTAssertTrue(ExplorerInstanceHealth.registration(.requireApplication).canCreateAccount)
        XCTAssertEqual(ExplorerInstanceHealth.registration(.closed).level, .bad)
        XCTAssertFalse(ExplorerInstanceHealth.registration(.closed).canCreateAccount)
        XCTAssertFalse(ExplorerInstanceHealth.registration(.unknown).canCreateAccount)
    }

    func test_trust() {
        XCTAssertEqual(ExplorerInstanceHealth.trust(score100: 96, suspicious: false).level, .good)
        XCTAssertEqual(ExplorerInstanceHealth.trust(score100: 60, suspicious: false).level, .ok)
        XCTAssertEqual(ExplorerInstanceHealth.trust(score100: 20, suspicious: false).level, .bad)
        XCTAssertEqual(ExplorerInstanceHealth.trust(score100: nil, suspicious: false).label, "Unrated")
        // Suspicious overrides a high score.
        XCTAssertEqual(ExplorerInstanceHealth.trust(score100: 96, suspicious: true).level, .bad)
        XCTAssertEqual(ExplorerInstanceHealth.trust(score100: 96, suspicious: true).label, "Low trust")
    }
}
