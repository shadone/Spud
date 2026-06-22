//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Network
import SpudUtilKit

/// Production reachability monitor backed by `NWPathMonitor`. Path updates
/// arrive on a private queue and are fanned out through a `Broadcaster` whose
/// current value is read on the main actor.
public final class ReachabilityMonitor: ReachabilityMonitoring {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "info.ddenis.Spud.reachability")
    private let broadcaster = Broadcaster<Bool>(true)

    public init() {
        monitor.pathUpdateHandler = { [broadcaster] path in
            broadcaster.send(path.status == .satisfied)
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    @MainActor public var isOnline: Bool {
        broadcaster.current
    }

    @MainActor public var statusStream: AsyncStream<Bool> {
        broadcaster.subscribe()
    }
}
