//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUtilKit
import XCTest
@testable import Spud

final class SearchURLDetectorTests: XCTestCase {
    private let known: (String) -> Bool = { ["lemmy.world", "beehaw.org"].contains($0) }

    private func detect(_ s: String) -> SearchURLSuggestion? {
        SearchURLDetector.detect(query: s, isKnownInstance: known)
    }

    // MARK: Known instance: classify drives kind + link.

    func test_knownPost_isPostKind_objectAtURL() throws {
        let s = try XCTUnwrap(detect("https://lemmy.world/post/123"))
        XCTAssertEqual(s.kind, .post)
        guard case let .objectAtURL(url) = s.link else { return XCTFail("expected .objectAtURL") }
        XCTAssertEqual(url.absoluteString, "https://lemmy.world/post/123")
    }

    func test_knownComment_isCommentKind() throws {
        let s = try XCTUnwrap(detect("https://lemmy.world/comment/9"))
        XCTAssertEqual(s.kind, .comment)
        guard case .objectAtURL = s.link else { return XCTFail("expected .objectAtURL") }
    }

    func test_knownUser_isUserKind() throws {
        let s = try XCTUnwrap(detect("https://beehaw.org/u/alice"))
        XCTAssertEqual(s.kind, .user)
    }

    func test_knownCommunity_isCommunityKind_communityLink() throws {
        let s = try XCTUnwrap(detect("https://lemmy.world/c/technology"))
        XCTAssertEqual(s.kind, .community)
        guard case let .community(name, instance) = s.link else { return XCTFail("expected .community") }
        XCTAssertEqual(name, "technology")
        XCTAssertEqual(instance.host, "lemmy.world")
    }

    func test_bareKnownInstance_isInstanceKind() throws {
        let s = try XCTUnwrap(detect("https://beehaw.org"))
        XCTAssertEqual(s.kind, .instance)
        guard case .instance = s.link else { return XCTFail("expected .instance") }
    }

    // MARK: Unknown host: path-shape fallback -> objectAtURL with derived kind.

    func test_unknownPost_isOffered_objectAtURL() throws {
        let s = try XCTUnwrap(detect("https://small.example/post/1"))
        XCTAssertEqual(s.kind, .post)
        guard case let .objectAtURL(url) = s.link else { return XCTFail("expected .objectAtURL") }
        XCTAssertEqual(url.absoluteString, "https://small.example/post/1")
    }

    func test_unknownComment_isOffered() throws {
        let s = try XCTUnwrap(detect("https://small.example/comment/7"))
        XCTAssertEqual(s.kind, .comment)
    }

    func test_unknownUser_isOffered() throws {
        let s = try XCTUnwrap(detect("https://small.example/u/bob"))
        XCTAssertEqual(s.kind, .user)
    }

    func test_unknownCommunity_isOffered_objectAtURL() throws {
        let s = try XCTUnwrap(detect("https://small.example/c/games"))
        XCTAssertEqual(s.kind, .community)
        guard case .objectAtURL = s.link else { return XCTFail("expected .objectAtURL for unknown host") }
    }

    func test_knownCommunity_qualifiedName_usesQualifiedHost() throws {
        let s = try XCTUnwrap(detect("https://lemmy.world/c/games@beehaw.org"))
        XCTAssertEqual(s.kind, .community)
        guard case let .community(name, instance) = s.link else { return XCTFail("expected .community") }
        XCTAssertEqual(name, "games")
        XCTAssertEqual(instance.host, "beehaw.org")
    }

    // MARK: Negatives.

    func test_bareUnknownHost_isNil() {
        XCTAssertNil(detect("https://example.com"))
    }

    func test_plainText_isNil() {
        XCTAssertNil(detect("cats"))
        XCTAssertNil(detect("how to make pasta"))
    }

    func test_nonHttpScheme_isNil() {
        XCTAssertNil(detect("mailto:a@b.com"))
        XCTAssertNil(detect("info.ddenis.spud://internal/post?postId=1&instance=x"))
    }

    func test_unknownNonLemmyPath_isNil() {
        XCTAssertNil(detect("https://news.example/article/abc"))
    }

    func test_postWithNonNumericId_isNil() {
        XCTAssertNil(detect("https://small.example/post/notanumber"))
    }

    func test_displayURL_dropsScheme() throws {
        let s = try XCTUnwrap(detect("https://lemmy.world/post/123"))
        XCTAssertEqual(s.displayURL, "lemmy.world/post/123")
    }

    func test_whitespaceIsTrimmed() throws {
        let s = try XCTUnwrap(detect("  https://lemmy.world/post/123  "))
        XCTAssertEqual(s.kind, .post)
    }
}
