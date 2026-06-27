//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import Spud

@MainActor
struct PrivacyScreenTests {
    private func resetMonitor() {
        let monitor = PrivacyScreenMonitor.shared
        while monitor.isShowingSensitiveContent {
            monitor.endSensitiveContent()
        }
    }

    @Test
    func shouldCover_truthTable() {
        // Not sensitive: never cover, regardless of scene / capture state.
        #expect(!PrivacyScreen.shouldCover(isSensitive: false, isSceneActive: true, isCaptured: false))
        #expect(!PrivacyScreen.shouldCover(isSensitive: false, isSceneActive: false, isCaptured: false))
        #expect(!PrivacyScreen.shouldCover(isSensitive: false, isSceneActive: false, isCaptured: true))

        // Sensitive + active + not captured: stay visible — the user opened it.
        #expect(!PrivacyScreen.shouldCover(isSensitive: true, isSceneActive: true, isCaptured: false))

        // Sensitive + backgrounded: cover for the app-switcher snapshot.
        #expect(PrivacyScreen.shouldCover(isSensitive: true, isSceneActive: false, isCaptured: false))

        // Sensitive + captured: cover for screen recording / mirroring, even while active.
        #expect(PrivacyScreen.shouldCover(isSensitive: true, isSceneActive: true, isCaptured: true))
    }

    @Test
    func monitor_countsAndBoolean() {
        resetMonitor()
        let monitor = PrivacyScreenMonitor.shared
        #expect(!monitor.isShowingSensitiveContent)

        monitor.beginSensitiveContent()
        #expect(monitor.isShowingSensitiveContent)

        // Two overlapping surfaces: the flag clears only when both end.
        monitor.beginSensitiveContent()
        monitor.endSensitiveContent()
        #expect(monitor.isShowingSensitiveContent)
        monitor.endSensitiveContent()
        #expect(!monitor.isShowingSensitiveContent)
    }

    @Test
    func monitor_doesNotGoNegative() {
        resetMonitor()
        let monitor = PrivacyScreenMonitor.shared
        monitor.endSensitiveContent() // underflow guard
        #expect(!monitor.isShowingSensitiveContent)
        #expect(monitor.sensitiveCount == 0)
    }

    @Test
    func sensitiveContentToken_balancesMonitor() {
        resetMonitor()
        let monitor = PrivacyScreenMonitor.shared
        let token = SensitiveContentToken()

        token.set(true)
        #expect(monitor.isShowingSensitiveContent)
        token.set(true) // idempotent — no double-count
        token.set(false)
        #expect(!monitor.isShowingSensitiveContent)
        token.set(false) // idempotent
        #expect(monitor.sensitiveCount == 0)
    }

    @Test
    func twoTokens_trackedIndependently() {
        resetMonitor()
        let monitor = PrivacyScreenMonitor.shared
        let a = SensitiveContentToken()
        let b = SensitiveContentToken()

        a.set(true)
        b.set(true)
        #expect(monitor.sensitiveCount == 2)
        a.set(false)
        #expect(monitor.isShowingSensitiveContent, "b is still active")
        b.set(false)
        #expect(!monitor.isShowingSensitiveContent)
    }

    @Test
    func monitor_postsNotificationOnlyOnBooleanTransition() {
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
        #expect(notifications == 2)
    }
}
