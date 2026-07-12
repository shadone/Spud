//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import Spud

/// Covers `PreferencesService.groupCrossPostsInFeed`: the "Group Cross-posts"
/// toggle that gates `CrossPostGrouper` in `PostListViewController.apply(rows:)`.
@MainActor
struct GroupCrossPostsInFeedPreferenceTests {
    @Test
    func defaultsToOn() {
        // A fresh, private UserDefaults suite has no persisted value, so the
        // service observes the declared default without clobbering `.standard`.
        let service = PreferencesService.ephemeral()
        #expect(service.groupCrossPostsInFeed == true)
    }

    @Test
    func streamEmitsOnChange() async {
        let service = PreferencesService.ephemeral()
        var iterator = service.groupCrossPostsInFeedStream.makeAsyncIterator()

        // Replay-on-subscribe: the first element is the current value, yielded
        // synchronously when the stream is created (see `Broadcaster.subscribe`).
        let replayed = await iterator.next()
        #expect(replayed == true)

        service.groupCrossPostsInFeed = false
        let changed = await iterator.next()
        #expect(changed == false)
    }
}
