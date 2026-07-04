//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
@testable import SpudDataKit

extension DownloadPacingConfig {
    /// A pacing config whose waits are instant (no real time passes) and whose
    /// jitter is fixed, so download tests assert OUTCOMES without waiting. Keeps
    /// the same retry/attempt counts as `.live` so retry behavior is realistic.
    static func immediate(
        jitter: @escaping @Sendable (ClosedRange<Double>) -> Double = { _ in 1.0 }
    ) -> DownloadPacingConfig {
        DownloadPacingConfig(
            minRequestInterval: .zero,
            maxRetryAttempts: 4,
            maxImageRetryAttempts: 2,
            retryBaseDelay: .milliseconds(500),
            retryMaxDelay: .seconds(30),
            serverPushbackCooldown: .seconds(8),
            now: { ContinuousClock().now },
            sleepUntil: { _ in },
            sleep: { _ in },
            jitter: jitter
        )
    }
}
