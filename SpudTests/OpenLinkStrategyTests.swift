//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Testing
@testable import Spud

/// Unit coverage for `resolveOpenStrategy` — the pure routing decision behind
/// `AppService.open(url:on:)`. WebKit/UIKit are not involved, so the rules are
/// exercised in isolation.
struct OpenLinkStrategyTests {
    // MARK: - Offline

    @Test
    func offlineWithArchive_opensReader() {
        let strategy = resolveOpenStrategy(
            isOnline: false,
            hasArchive: true,
            preference: .safariViewController
        )
        #expect(strategy == .archiveReader)
    }

    @Test
    func offlineWithArchive_opensReader_regardlessOfPreference() {
        // The preference governs the *online* path; offline + archive always
        // routes to the reader.
        for preference in Preferences.OpenExternalLink.allCases {
            let strategy = resolveOpenStrategy(
                isOnline: false,
                hasArchive: true,
                preference: preference
            )
            #expect(strategy == .archiveReader)
        }
    }

    @Test
    func offlineWithoutArchive_signalsNoArchive() {
        // No broken SFSafariViewController offline — the caller shows a toast.
        for preference in Preferences.OpenExternalLink.allCases {
            let strategy = resolveOpenStrategy(
                isOnline: false,
                hasArchive: false,
                preference: preference
            )
            #expect(strategy == .offlineNoArchive)
        }
    }

    // MARK: - Online (existing behavior, archive ignored)

    @Test
    func onlineSafariPreference_opensSafari() {
        let strategy = resolveOpenStrategy(
            isOnline: true,
            hasArchive: false,
            preference: .safariViewController
        )
        #expect(strategy == .safari)
    }

    @Test
    func onlineBrowserPreference_opensBrowser() {
        let strategy = resolveOpenStrategy(
            isOnline: true,
            hasArchive: false,
            preference: .browser
        )
        #expect(strategy == .browser)
    }

    @Test(arguments: Preferences.OpenExternalLink.allCases)
    func online_prefersLivePage_ignoringArchive(preference: Preferences.OpenExternalLink) {
        // Online always uses the live page regardless of whether an archive
        // exists — the snapshot is strictly a no-connectivity fallback.
        let withArchive = resolveOpenStrategy(
            isOnline: true,
            hasArchive: true,
            preference: preference
        )
        let withoutArchive = resolveOpenStrategy(
            isOnline: true,
            hasArchive: false,
            preference: preference
        )
        #expect(withArchive == withoutArchive)
        #expect(withArchive != .archiveReader)
        #expect(withArchive != .offlineNoArchive)
    }
}
