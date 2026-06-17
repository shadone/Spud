//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import OSLog

/// Lightweight os_signpost wrapper for measuring image time-to-first-pixel and
/// decode in Instruments. Always-on (signposts are production-safe and cheap).
struct ImageLoadingSignposter {
    private let signposter = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "info.ddenis.Spud",
        category: "ImageLoading"
    )

    func interval<T>(_ name: StaticString, _ work: () async throws -> T) async rethrows -> T {
        let state = signposter.beginInterval(name, id: signposter.makeSignpostID())
        defer { signposter.endInterval(name, state) }
        return try await work()
    }

    func beginInterval(_ name: StaticString) -> OSSignpostIntervalState {
        signposter.beginInterval(name, id: signposter.makeSignpostID())
    }

    func endInterval(_ name: StaticString, _ state: OSSignpostIntervalState) {
        signposter.endInterval(name, state)
    }
}
