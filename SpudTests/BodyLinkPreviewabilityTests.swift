//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUtilKit
import Testing
@testable import Spud

/// `BodyLinkPreviewability.classify` is the load-bearing decision behind the
/// inline body-link long-press menu: a browser-style preview is attached ONLY
/// for a genuine `http(s)` web URL. Internal links (`spud-markdown://` mentions/
/// communities/objects and the `info.ddenis.spud://` app scheme) and any other
/// non-`http(s)` scheme are `.notPreviewable`, so the menu carries no preview —
/// the system link preview traps on a non-`http(s)` URL (the mention crash).
struct BodyLinkPreviewabilityTests {
    private func classify(_ string: String) throws -> BodyLinkPreviewability {
        try BodyLinkPreviewability.classify(#require(URL(string: string)))
    }

    // MARK: - Not previewable (menu only, no crash-prone preview)

    @Test
    func spudMarkdownMention_isNotPreviewable() throws {
        #expect(try classify("spud-markdown://mention?name=hiking&instance=fediverse.social") == .notPreviewable)
    }

    @Test
    func spudMarkdownCommunity_isNotPreviewable() throws {
        #expect(try classify("spud-markdown://community?name=technology&instance=lemmy.world") == .notPreviewable)
    }

    @Test
    func spudMarkdownObject_isNotPreviewable() throws {
        #expect(try classify("spud-markdown://object?url=https%3A%2F%2Flemmy.world%2Fpost%2F12345") == .notPreviewable)
    }

    @Test
    func internalSpudScheme_isNotPreviewable() throws {
        #expect(try classify("info.ddenis.spud://internal/community?name=tech&instance=https%3A%2F%2Flemmy.world") == .notPreviewable)
    }

    @Test
    func mailtoScheme_isNotPreviewable() throws {
        #expect(try classify("mailto:someone@example.com") == .notPreviewable)
    }

    // MARK: - Previewable (genuine web URLs)

    @Test
    func httpsWebURL_isPreviewable() throws {
        #expect(try classify("https://discuss.tchncs.de/post/63824857") == .previewable)
    }

    @Test
    func httpWebURL_isPreviewable() throws {
        #expect(try classify("http://example.com/article") == .previewable)
    }

    @Test
    func httpsLemmyWebURL_isPreviewable() throws {
        // A Lemmy web link is still a genuine http(s) URL, so it keeps a preview
        // (its "Open in Spud" action is decided separately, at menu-build time).
        #expect(try classify("https://lemmy.world/c/technology") == .previewable)
    }
}
