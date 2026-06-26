//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUtilKit
import XCTest
@testable import Spud

final class MarkdownInternalLinkTests: XCTestCase {
    private func resolve(_ string: String) -> URL? {
        guard let url = URL(string: string) else {
            XCTFail("Could not construct URL from: \(string)")
            return nil
        }
        return MarkdownInternalLink.resolve(url)
    }

    // MARK: - Mention (user)

    func test_mentionURL_resolvesToObjectAtURL_withUserPath() throws {
        let result = try XCTUnwrap(resolve("spud-markdown://mention?name=alice&instance=lemmy.world"))
        let link = try XCTUnwrap(result.spud)
        guard case let .objectAtURL(url) = link else {
            return XCTFail("expected .objectAtURL, got \(link)")
        }
        XCTAssertEqual(url.absoluteString, "https://lemmy.world/u/alice")
    }

    func test_mentionURL_withSpecialCharsInName_resolvesCorrectly() throws {
        let result = try XCTUnwrap(resolve("spud-markdown://mention?name=alice_bob&instance=beehaw.org"))
        let link = try XCTUnwrap(result.spud)
        guard case let .objectAtURL(url) = link else {
            return XCTFail("expected .objectAtURL, got \(link)")
        }
        XCTAssertEqual(url.absoluteString, "https://beehaw.org/u/alice_bob")
    }

    // MARK: - Community

    func test_communityURL_resolvesToCommunityLink() throws {
        let result = try XCTUnwrap(resolve("spud-markdown://community?name=technology&instance=lemmy.world"))
        let link = try XCTUnwrap(result.spud)
        guard case let .community(name, instance) = link else {
            return XCTFail("expected .community, got \(link)")
        }
        XCTAssertEqual(name, "technology")
        XCTAssertEqual(instance.host, "lemmy.world")
    }

    func test_communityURL_differentInstance_resolvesCorrectInstance() throws {
        let result = try XCTUnwrap(resolve("spud-markdown://community?name=news&instance=beehaw.org"))
        let link = try XCTUnwrap(result.spud)
        guard case let .community(name, instance) = link else {
            return XCTFail("expected .community, got \(link)")
        }
        XCTAssertEqual(name, "news")
        XCTAssertEqual(instance.host, "beehaw.org")
    }

    // MARK: - Object (post / comment)

    func test_objectURL_resolvesToObjectAtURL() throws {
        let result = try XCTUnwrap(resolve("spud-markdown://object?url=https%3A%2F%2Flemmy.world%2Fpost%2F12345"))
        let link = try XCTUnwrap(result.spud)
        guard case let .objectAtURL(url) = link else {
            return XCTFail("expected .objectAtURL, got \(link)")
        }
        XCTAssertEqual(url.absoluteString, "https://lemmy.world/post/12345")
    }

    func test_objectURL_missingURL_returnsNil() {
        XCTAssertNil(resolve("spud-markdown://object"))
    }

    // MARK: - Non-spud-markdown URLs return nil

    func test_httpsURL_returnsNil() {
        XCTAssertNil(resolve("https://lemmy.world/c/technology"))
    }

    func test_internalSpudURL_returnsNil() {
        XCTAssertNil(resolve("info.ddenis.spud://internal/community?name=tech&instance=https%3A%2F%2Flemmy.world"))
    }

    func test_unknownSpudMarkdownHost_returnsNil() {
        XCTAssertNil(resolve("spud-markdown://post?name=test&instance=lemmy.world"))
    }

    func test_mentionURL_missingName_returnsNil() {
        XCTAssertNil(resolve("spud-markdown://mention?instance=lemmy.world"))
    }

    func test_mentionURL_missingInstance_returnsNil() {
        XCTAssertNil(resolve("spud-markdown://mention?name=alice"))
    }

    func test_communityURL_missingName_returnsNil() {
        XCTAssertNil(resolve("spud-markdown://community?instance=lemmy.world"))
    }
}
