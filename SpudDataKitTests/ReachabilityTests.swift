//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import SpudDataKit

@MainActor
final class ReachabilityTests: XCTestCase {
    func testStaticMonitorReportsInitialValueAndUpdates() async {
        let monitor = StaticReachabilityMonitor(isOnline: false)
        XCTAssertFalse(monitor.isOnline)

        var iterator = monitor.statusStream.makeAsyncIterator()
        let first = await iterator.next()
        XCTAssertEqual(first, false)

        monitor.setOnline(true)
        XCTAssertTrue(monitor.isOnline)
        let second = await iterator.next()
        XCTAssertEqual(second, true)
    }
}
