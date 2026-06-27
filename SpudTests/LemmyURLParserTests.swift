//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUtilKit
import Testing
@testable import Spud

struct LemmyURLParserTests {
    private let known: (String) -> Bool = { ["lemmy.world", "beehaw.org"].contains($0) }

    private func classify(_ s: String) -> URL.SpudInternalLink? {
        LemmyURLParser.classify(url: URL(string: s)!, isKnownInstance: known)
    }

    @Test
    func postURL_onKnownInstance_isObjectAtURL() throws {
        let url = try #require(URL(string: "https://lemmy.world/post/123"))
        guard case let .objectAtURL(parsed)? = classify(url.absoluteString) else {
            Issue.record("expected .objectAtURL")
            return
        }
        #expect(parsed == url)
    }

    @Test
    func userURL_onKnownInstance_isObjectAtURL() {
        guard case .objectAtURL? = classify("https://beehaw.org/u/alice") else {
            Issue.record("expected .objectAtURL")
            return
        }
    }

    @Test
    func communityURL_localName_isCommunityAtLinkHost() {
        guard case let .community(name, instance)? = classify("https://lemmy.world/c/technology") else {
            Issue.record("expected .community")
            return
        }
        #expect(name == "technology")
        #expect(instance.host == "lemmy.world")
    }

    @Test
    func communityURL_qualifiedName_usesQualifiedHost() {
        guard case let .community(name, instance)? = classify("https://lemmy.world/c/technology@beehaw.org") else {
            Issue.record("expected .community")
            return
        }
        #expect(name == "technology")
        #expect(instance.host == "beehaw.org")
    }

    @Test
    func bareKnownInstance_isInstance() {
        guard case let .instance(instance)? = classify("https://beehaw.org") else {
            Issue.record("expected .instance")
            return
        }
        #expect(instance.host == "beehaw.org")
    }

    @Test
    func bareUnknownDomain_isNil() {
        #expect(classify("https://example.com") == nil)
    }

    @Test
    func postPathOnUnknownDomain_isNil() {
        #expect(classify("https://example.com/post/1") == nil)
    }

    @Test
    func commentURL_onKnownInstance_isObjectAtURL() throws {
        let url = try #require(URL(string: "https://lemmy.world/comment/9"))
        guard case let .objectAtURL(parsed)? = classify(url.absoluteString) else {
            Issue.record("expected .objectAtURL")
            return
        }
        #expect(parsed == url)
    }

    @Test
    func commentPathOnUnknownDomain_isNil() {
        #expect(classify("https://example.com/comment/9") == nil)
    }

    @Test
    func commentURL_withNonNumericId_isNil() {
        #expect(classify("https://lemmy.world/comment/notanumber") == nil)
    }

    // MARK: - Frontend post URL (/c/<community>/p/<id>[/<slug>])

    @Test
    func frontendPostURL_withSlug_resolvesCanonicalPost() {
        guard case let .objectAtURL(parsed)? =
            classify("https://lemmy.world/c/opensource/p/1784296/favorite-open-source-game")
        else {
            Issue.record("expected .objectAtURL")
            return
        }
        #expect(parsed.absoluteString == "https://lemmy.world/post/1784296")
    }

    @Test
    func frontendPostURL_withoutSlug_resolvesCanonicalPost() {
        guard case let .objectAtURL(parsed)? = classify("https://lemmy.world/c/opensource/p/1784296") else {
            Issue.record("expected .objectAtURL")
            return
        }
        #expect(parsed.absoluteString == "https://lemmy.world/post/1784296")
    }

    @Test
    func frontendPostURL_onUnknownInstance_isNil() {
        // classify gates content paths on known instances; the search detector's
        // fallback is what offers unknown-host frontend post URLs.
        #expect(classify("https://feddit.online/c/opensource/p/1784296/slug") == nil)
    }

    @Test
    func frontendPostURL_withNonNumericId_isNil() {
        #expect(classify("https://lemmy.world/c/opensource/p/notanumber/slug") == nil)
    }

    @Test
    func communityMention_isCommunity() {
        let mentions = LemmyURLParser.mentions(in: "see !technology@beehaw.org now")
        #expect(mentions.count == 1)
        guard case let .community(name, instance) = mentions[0].link else {
            Issue.record("expected .community")
            return
        }
        #expect(name == "technology")
        #expect(instance.host == "beehaw.org")
    }

    @Test
    func userMention_isObjectAtURL_toUserPath() {
        let mentions = LemmyURLParser.mentions(in: "ping @alice@lemmy.world ok")
        #expect(mentions.count == 1)
        guard case let .objectAtURL(url) = mentions[0].link else {
            Issue.record("expected .objectAtURL")
            return
        }
        #expect(url.absoluteString == "https://lemmy.world/u/alice")
    }

    @Test
    func mentions_returnedInTextOrder() {
        // A user mention appears before a community mention in the text; the
        // result must reflect appearance order, not match-pass order.
        let mentions = LemmyURLParser.mentions(in: "@alice@a.example !tech@b.example")
        #expect(mentions.count == 2)
        guard case .objectAtURL = mentions[0].link else {
            Issue.record("first mention should be the user mention")
            return
        }
        guard case .community = mentions[1].link else {
            Issue.record("second mention should be the community mention")
            return
        }
        #expect(mentions[0].range.location < mentions[1].range.location)
    }

    @Test
    func communityMention_atStringStart_matches() {
        let mentions = LemmyURLParser.mentions(in: "!tech@beehaw.org leads the line")
        #expect(mentions.count == 1)
        #expect(mentions[0].range.location == 0)
    }

    @Test
    func postURL_withNonNumericId_isNil() {
        #expect(classify("https://lemmy.world/post/notanumber") == nil)
    }
}
