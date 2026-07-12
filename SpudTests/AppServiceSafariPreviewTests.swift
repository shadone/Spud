//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SafariServices
import SpudDataKit
import Testing
@testable import Spud

/// `SFSafariViewController(url:)` traps when handed a non-`http(s)` URL, so
/// `AppService.safariViewControllerForPreview(url:)` must return `nil` for any
/// such URL instead of constructing (and crashing on) one. The mention
/// long-press crash reached this path through a context-menu preview provider
/// for a `spud-markdown://` URL.
@MainActor
struct AppServiceSafariPreviewTests {
    private func makeAppService() throws -> AppService {
        try AppService(
            preferencesService: PreferencesService.ephemeral(),
            appDatabase: AppDatabase.inMemory(),
            reachabilityMonitor: StaticReachabilityMonitor(isOnline: true),
            webArchiveStore: nil
        )
    }

    @Test
    func spudMarkdownMentionURL_returnsNil() throws {
        let url = try #require(URL(string: "spud-markdown://mention?name=hiking&instance=fediverse.social"))
        #expect(try makeAppService().safariViewControllerForPreview(url: url) == nil)
    }

    @Test
    func mailtoURL_returnsNil() throws {
        let url = try #require(URL(string: "mailto:someone@example.com"))
        #expect(try makeAppService().safariViewControllerForPreview(url: url) == nil)
    }

    @Test
    func internalSpudSchemeURL_returnsNil() throws {
        let url = try #require(URL(string: "info.ddenis.spud://internal/community?name=tech&instance=https%3A%2F%2Flemmy.world"))
        #expect(try makeAppService().safariViewControllerForPreview(url: url) == nil)
    }

    @Test
    func httpsWebURL_returnsSafariViewController() throws {
        let url = try #require(URL(string: "https://discuss.tchncs.de/post/63824857"))
        #expect(try makeAppService().safariViewControllerForPreview(url: url) != nil)
    }

    @Test
    func httpWebURL_returnsSafariViewController() throws {
        let url = try #require(URL(string: "http://example.com/article"))
        #expect(try makeAppService().safariViewControllerForPreview(url: url) != nil)
    }
}
