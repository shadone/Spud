//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import Spud

@MainActor
final class PrivacyScreenTests: XCTestCase {
    private func resetMonitor() {
        let monitor = PrivacyScreenMonitor.shared
        while monitor.isShowingSensitiveContent {
            monitor.endSensitiveContent()
        }
    }

    func test_shouldCover_truthTable() {
        // Not sensitive: never cover, regardless of scene / capture state.
        XCTAssertFalse(PrivacyScreen.shouldCover(isSensitive: false, isSceneActive: true, isCaptured: false))
        XCTAssertFalse(PrivacyScreen.shouldCover(isSensitive: false, isSceneActive: false, isCaptured: false))
        XCTAssertFalse(PrivacyScreen.shouldCover(isSensitive: false, isSceneActive: false, isCaptured: true))

        // Sensitive + active + not captured: stay visible — the user opened it.
        XCTAssertFalse(PrivacyScreen.shouldCover(isSensitive: true, isSceneActive: true, isCaptured: false))

        // Sensitive + backgrounded: cover for the app-switcher snapshot.
        XCTAssertTrue(PrivacyScreen.shouldCover(isSensitive: true, isSceneActive: false, isCaptured: false))

        // Sensitive + captured: cover for screen recording / mirroring, even while active.
        XCTAssertTrue(PrivacyScreen.shouldCover(isSensitive: true, isSceneActive: true, isCaptured: true))
    }

    func test_monitor_countsAndBoolean() {
        resetMonitor()
        let monitor = PrivacyScreenMonitor.shared
        XCTAssertFalse(monitor.isShowingSensitiveContent)

        monitor.beginSensitiveContent()
        XCTAssertTrue(monitor.isShowingSensitiveContent)

        // Two overlapping surfaces: the flag clears only when both end.
        monitor.beginSensitiveContent()
        monitor.endSensitiveContent()
        XCTAssertTrue(monitor.isShowingSensitiveContent)
        monitor.endSensitiveContent()
        XCTAssertFalse(monitor.isShowingSensitiveContent)
    }

    func test_monitor_doesNotGoNegative() {
        resetMonitor()
        let monitor = PrivacyScreenMonitor.shared
        monitor.endSensitiveContent() // underflow guard
        XCTAssertFalse(monitor.isShowingSensitiveContent)
        XCTAssertEqual(monitor.sensitiveCount, 0)
    }

    func test_monitor_postsNotificationOnlyOnBooleanTransition() {
        resetMonitor()
        let monitor = PrivacyScreenMonitor.shared

        var notifications = 0
        let token = NotificationCenter.default.addObserver(
            forName: .privacyScreenSensitiveContentDidChange,
            object: nil,
            queue: nil
        ) { _ in notifications += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        monitor.beginSensitiveContent() // 0 -> 1: posts
        monitor.beginSensitiveContent() // 1 -> 2: no post
        monitor.endSensitiveContent() //   2 -> 1: no post
        monitor.endSensitiveContent() //   1 -> 0: posts
        XCTAssertEqual(notifications, 2)
    }
}
