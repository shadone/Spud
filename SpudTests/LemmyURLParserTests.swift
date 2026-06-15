//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUtilKit
import XCTest
@testable import Spud

final class LemmyURLParserTests: XCTestCase {
    private let known: (String) -> Bool = { ["lemmy.world", "beehaw.org"].contains($0) }

    private func classify(_ s: String) -> URL.SpudInternalLink? {
        LemmyURLParser.classify(url: URL(string: s)!, isKnownInstance: known)
    }

    func test_postURL_onKnownInstance_isObjectAtURL() throws {
        let url = try XCTUnwrap(URL(string: "https://lemmy.world/post/123"))
        guard case let .objectAtURL(parsed)? = classify(url.absoluteString) else {
            return XCTFail("expected .objectAtURL")
        }
        XCTAssertEqual(parsed, url)
    }

    func test_userURL_onKnownInstance_isObjectAtURL() {
        guard case .objectAtURL? = classify("https://beehaw.org/u/alice") else {
            return XCTFail("expected .objectAtURL")
        }
    }

    func test_communityURL_localName_isCommunityAtLinkHost() {
        guard case let .community(name, instance)? = classify("https://lemmy.world/c/technology") else {
            return XCTFail("expected .community")
        }
        XCTAssertEqual(name, "technology")
        XCTAssertEqual(instance.host, "lemmy.world")
    }

    func test_communityURL_qualifiedName_usesQualifiedHost() {
        guard case let .community(name, instance)? = classify("https://lemmy.world/c/technology@beehaw.org") else {
            return XCTFail("expected .community")
        }
        XCTAssertEqual(name, "technology")
        XCTAssertEqual(instance.host, "beehaw.org")
    }

    func test_bareKnownInstance_isInstance() {
        guard case let .instance(instance)? = classify("https://beehaw.org") else {
            return XCTFail("expected .instance")
        }
        XCTAssertEqual(instance.host, "beehaw.org")
    }

    func test_bareUnknownDomain_isNil() {
        XCTAssertNil(classify("https://example.com"))
    }

    func test_postPathOnUnknownDomain_isNil() {
        XCTAssertNil(classify("https://example.com/post/1"))
    }

    func test_commentURL_isNil_deferred() {
        XCTAssertNil(classify("https://lemmy.world/comment/9"))
    }

    func test_communityMention_isCommunity() {
        let mentions = LemmyURLParser.mentions(in: "see !technology@beehaw.org now")
        XCTAssertEqual(mentions.count, 1)
        guard case let .community(name, instance) = mentions[0].link else {
            return XCTFail("expected .community")
        }
        XCTAssertEqual(name, "technology")
        XCTAssertEqual(instance.host, "beehaw.org")
    }

    func test_userMention_isObjectAtURL_toUserPath() {
        let mentions = LemmyURLParser.mentions(in: "ping @alice@lemmy.world ok")
        XCTAssertEqual(mentions.count, 1)
        guard case let .objectAtURL(url) = mentions[0].link else {
            return XCTFail("expected .objectAtURL")
        }
        XCTAssertEqual(url.absoluteString, "https://lemmy.world/u/alice")
    }
}
