//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudDataKit

struct DownloadPacingConfigTests {
    @Test
    func liveConfigHasSpecifiedTunables() {
        let c = DownloadPacingConfig.live
        #expect(c.minRequestInterval == .milliseconds(200))
        #expect(c.maxRetryAttempts == 4)
        #expect(c.maxImageRetryAttempts == 2)
        #expect(c.retryBaseDelay == .milliseconds(500))
        #expect(c.retryMaxDelay == .seconds(30))
        #expect(c.serverPushbackCooldown == .seconds(8))
    }

    @Test
    func finishedWithWarningStillCompletesFully() {
        let p = OfflineDownloadProgress(
            phase: .finished, postsFetched: 80, totalPosts: 80, itemsCompleted: 80,
            warningMessage: "Downloaded 80 posts — some of the feed couldn't be reached."
        )
        #expect(p.fractionCompleted == 1)
        #expect(p.warningMessage != nil)
    }

    @Test
    func warningMessageDefaultsNil() {
        let p = OfflineDownloadProgress(phase: .finished, postsFetched: 10, totalPosts: 10, itemsCompleted: 10)
        #expect(p.warningMessage == nil)
    }
}
