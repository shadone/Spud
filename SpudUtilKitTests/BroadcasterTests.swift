//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Testing
@testable import SpudUtilKit

struct BroadcasterTests {
    @Test
    func subscribeReplaysCurrentThenReceivesUpdates() async {
        let broadcaster = Broadcaster<Int>(1)
        var iterator = broadcaster.subscribe().makeAsyncIterator()

        let first = await iterator.next()
        #expect(first == 1)

        broadcaster.send(2)
        let second = await iterator.next()
        #expect(second == 2)
        #expect(broadcaster.current == 2)
    }
}
