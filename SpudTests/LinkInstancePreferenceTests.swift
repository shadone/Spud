//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import Spud

@MainActor
final class LinkInstancePreferenceTests: XCTestCase {
    func test_defaults_preserveCurrentBehavior() {
        // Clear any persisted values so we observe the declared defaults.
        UserDefaults.standard.removeObject(forKey: "openInBrowserInstance")
        UserDefaults.standard.removeObject(forKey: "shareLinkInstance")

        let service = PreferencesService()

        XCTAssertEqual(service.openInBrowserInstance, .myInstance)
        XCTAssertEqual(service.shareLinkInstance, .originalInstance)
    }

    func test_title_isStable() {
        XCTAssertEqual(Preferences.LinkInstance.myInstance.title, "My Instance")
        XCTAssertEqual(Preferences.LinkInstance.originalInstance.title, "Original Instance")
    }
}
