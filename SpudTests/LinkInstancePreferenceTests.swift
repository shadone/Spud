//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import Spud

@MainActor
struct LinkInstancePreferenceTests {
    @Test
    func defaults_preserveCurrentBehavior() {
        // A fresh, private UserDefaults suite has no persisted values, so the
        // service observes the declared defaults without clobbering `.standard`.
        let service = PreferencesService.ephemeral()

        #expect(service.openInBrowserInstance == .myInstance)
        #expect(service.shareLinkInstance == .originalInstance)
    }

    @Test
    func title_isStable() {
        #expect(Preferences.LinkInstance.myInstance.title == "My Instance")
        #expect(Preferences.LinkInstance.originalInstance.title == "Original Instance")
    }
}
