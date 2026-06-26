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

    func test_commentURL_onKnownInstance_isObjectAtURL() throws {
        let url = try XCTUnwrap(URL(string: "https://lemmy.world/comment/9"))
        guard case let .objectAtURL(parsed)? = classify(url.absoluteString) else {
            return XCTFail("expected .objectAtURL")
        }
        XCTAssertEqual(parsed, url)
    }

    func test_commentPathOnUnknownDomain_isNil() {
        XCTAssertNil(classify("https://example.com/comment/9"))
    }

    func test_commentURL_withNonNumericId_isNil() {
        XCTAssertNil(classify("https://lemmy.world/comment/notanumber"))
    }

    // MARK: - Frontend post URL (/c/<community>/p/<id>[/<slug>])

    func test_frontendPostURL_withSlug_resolvesCanonicalPost() {
        guard case let .objectAtURL(parsed)? =
            classify("https://lemmy.world/c/opensource/p/1784296/favorite-open-source-game")
        else {
            return XCTFail("expected .objectAtURL")
        }
        XCTAssertEqual(parsed.absoluteString, "https://lemmy.world/post/1784296")
    }

    func test_frontendPostURL_withoutSlug_resolvesCanonicalPost() {
        guard case let .objectAtURL(parsed)? = classify("https://lemmy.world/c/opensource/p/1784296") else {
            return XCTFail("expected .objectAtURL")
        }
        XCTAssertEqual(parsed.absoluteString, "https://lemmy.world/post/1784296")
    }

    func test_frontendPostURL_onUnknownInstance_isNil() {
        // classify gates content paths on known instances; the search detector's
        // fallback is what offers unknown-host frontend post URLs.
        XCTAssertNil(classify("https://feddit.online/c/opensource/p/1784296/slug"))
    }

    func test_frontendPostURL_withNonNumericId_isNil() {
        XCTAssertNil(classify("https://lemmy.world/c/opensource/p/notanumber/slug"))
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

    func test_mentions_returnedInTextOrder() {
        // A user mention appears before a community mention in the text; the
        // result must reflect appearance order, not match-pass order.
        let mentions = LemmyURLParser.mentions(in: "@alice@a.example !tech@b.example")
        XCTAssertEqual(mentions.count, 2)
        guard case .objectAtURL = mentions[0].link else {
            return XCTFail("first mention should be the user mention")
        }
        guard case .community = mentions[1].link else {
            return XCTFail("second mention should be the community mention")
        }
        XCTAssertLessThan(mentions[0].range.location, mentions[1].range.location)
    }

    func test_communityMention_atStringStart_matches() {
        let mentions = LemmyURLParser.mentions(in: "!tech@beehaw.org leads the line")
        XCTAssertEqual(mentions.count, 1)
        XCTAssertEqual(mentions[0].range.location, 0)
    }

    func test_postURL_withNonNumericId_isNil() {
        XCTAssertNil(classify("https://lemmy.world/post/notanumber"))
    }
}
