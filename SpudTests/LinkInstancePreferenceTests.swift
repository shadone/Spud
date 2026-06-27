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
        // Clear any persisted values so we observe the declared defaults.
        UserDefaults.standard.removeObject(forKey: "openInBrowserInstance")
        UserDefaults.standard.removeObject(forKey: "shareLinkInstance")

        let service = PreferencesService()

        #expect(service.openInBrowserInstance == .myInstance)
        #expect(service.shareLinkInstance == .originalInstance)
    }

    @Test
    func title_isStable() {
        #expect(Preferences.LinkInstance.myInstance.title == "My Instance")
        #expect(Preferences.LinkInstance.originalInstance.title == "Original Instance")
    }
}
