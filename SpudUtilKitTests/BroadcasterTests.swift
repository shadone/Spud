//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import SpudUtilKit

final class BroadcasterTests: XCTestCase {
    func testSubscribeReplaysCurrentThenReceivesUpdates() async {
        let broadcaster = Broadcaster<Int>(1)
        var iterator = broadcaster.subscribe().makeAsyncIterator()

        let first = await iterator.next()
        XCTAssertEqual(first, 1)

        broadcaster.send(2)
        let second = await iterator.next()
        XCTAssertEqual(second, 2)
        XCTAssertEqual(broadcaster.current, 2)
    }
}
