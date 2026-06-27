//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Testing
@testable import SpudDataKit

@MainActor
struct ReachabilityTests {
    @Test
    func staticMonitorReportsInitialValueAndUpdates() async {
        let monitor = StaticReachabilityMonitor(isOnline: false)
        #expect(!(monitor.isOnline))

        var iterator = monitor.statusStream.makeAsyncIterator()
        let first = await iterator.next()
        #expect(first == false)

        monitor.setOnline(true)
        #expect(monitor.isOnline)
        let second = await iterator.next()
        #expect(second == true)
    }
}
