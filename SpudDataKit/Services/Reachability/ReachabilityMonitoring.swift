//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUtilKit

/// Live network reachability. `isOnline` is a synchronous snapshot used to
/// classify failures; `statusStream` replays the current value on subscribe
/// and yields on every change (used to auto-retry when connectivity returns).
public protocol ReachabilityMonitoring: Sendable {
    @MainActor var isOnline: Bool { get }
    @MainActor var statusStream: AsyncStream<Bool> { get }
}

@MainActor
public protocol HasReachabilityMonitor {
    var reachabilityMonitor: ReachabilityMonitoring { get }
}

/// A reachability monitor with a value the test sets directly.
@MainActor
public final class StaticReachabilityMonitor: ReachabilityMonitoring {
    private let broadcaster: Broadcaster<Bool>

    public init(isOnline: Bool) {
        broadcaster = Broadcaster(isOnline)
    }

    public var isOnline: Bool {
        broadcaster.current
    }

    public var statusStream: AsyncStream<Bool> {
        broadcaster.subscribe()
    }

    public func setOnline(_ value: Bool) {
        broadcaster.send(value)
    }
}
