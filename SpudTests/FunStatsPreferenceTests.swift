//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import Spud

@MainActor
struct FunStatsPreferenceTests {
    @Test
    func funStatsCollectionEnabled_defaultsToTrue() {
        let preferences = PreferencesService.ephemeral()
        #expect(preferences.funStatsCollectionEnabled == true)
    }

    @Test
    func funStatsCollectionEnabled_roundTrips() {
        let preferences = PreferencesService.ephemeral()
        preferences.funStatsCollectionEnabled = false
        #expect(preferences.funStatsCollectionEnabled == false)
    }

    @Test
    func funStatsCollectionEnabledStream_replaysCurrentValue() async {
        let preferences = PreferencesService.ephemeral()
        preferences.funStatsCollectionEnabled = false
        var iterator = preferences.funStatsCollectionEnabledStream.makeAsyncIterator()
        let first = await iterator.next()
        #expect(first == false)
    }
}
