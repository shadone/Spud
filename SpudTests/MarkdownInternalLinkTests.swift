//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUtilKit
import Testing
@testable import Spud

struct MarkdownInternalLinkTests {
    private func resolve(_ string: String) -> URL? {
        guard let url = URL(string: string) else {
            Issue.record("Could not construct URL from: \(string)")
            return nil
        }
        return MarkdownInternalLink.resolve(url)
    }

    // MARK: - Mention (user)

    @Test
    func mentionURL_resolvesToObjectAtURL_withUserPath() throws {
        let result = try #require(resolve("spud-markdown://mention?name=alice&instance=lemmy.world"))
        let link = try #require(result.spud)
        guard case let .objectAtURL(url) = link else {
            Issue.record("expected .objectAtURL, got \(link)")
            return
        }
        #expect(url.absoluteString == "https://lemmy.world/u/alice")
    }

    @Test
    func mentionURL_withSpecialCharsInName_resolvesCorrectly() throws {
        let result = try #require(resolve("spud-markdown://mention?name=alice_bob&instance=beehaw.org"))
        let link = try #require(result.spud)
        guard case let .objectAtURL(url) = link else {
            Issue.record("expected .objectAtURL, got \(link)")
            return
        }
        #expect(url.absoluteString == "https://beehaw.org/u/alice_bob")
    }

    // MARK: - Community

    @Test
    func communityURL_resolvesToCommunityLink() throws {
        let result = try #require(resolve("spud-markdown://community?name=technology&instance=lemmy.world"))
        let link = try #require(result.spud)
        guard case let .community(name, instance) = link else {
            Issue.record("expected .community, got \(link)")
            return
        }
        #expect(name == "technology")
        #expect(instance.host == "lemmy.world")
    }

    @Test
    func communityURL_differentInstance_resolvesCorrectInstance() throws {
        let result = try #require(resolve("spud-markdown://community?name=news&instance=beehaw.org"))
        let link = try #require(result.spud)
        guard case let .community(name, instance) = link else {
            Issue.record("expected .community, got \(link)")
            return
        }
        #expect(name == "news")
        #expect(instance.host == "beehaw.org")
    }

    // MARK: - Object (post / comment)

    @Test
    func objectURL_resolvesToObjectAtURL() throws {
        let result = try #require(resolve("spud-markdown://object?url=https%3A%2F%2Flemmy.world%2Fpost%2F12345"))
        let link = try #require(result.spud)
        guard case let .objectAtURL(url) = link else {
            Issue.record("expected .objectAtURL, got \(link)")
            return
        }
        #expect(url.absoluteString == "https://lemmy.world/post/12345")
    }

    @Test
    func objectURL_missingURL_returnsNil() {
        #expect(resolve("spud-markdown://object") == nil)
    }

    // MARK: - Non-spud-markdown URLs return nil

    @Test
    func httpsURL_returnsNil() {
        #expect(resolve("https://lemmy.world/c/technology") == nil)
    }

    @Test
    func internalSpudURL_returnsNil() {
        #expect(resolve("info.ddenis.spud://internal/community?name=tech&instance=https%3A%2F%2Flemmy.world") == nil)
    }

    @Test
    func unknownSpudMarkdownHost_returnsNil() {
        #expect(resolve("spud-markdown://post?name=test&instance=lemmy.world") == nil)
    }

    @Test
    func mentionURL_missingName_returnsNil() {
        #expect(resolve("spud-markdown://mention?instance=lemmy.world") == nil)
    }

    @Test
    func mentionURL_missingInstance_returnsNil() {
        #expect(resolve("spud-markdown://mention?name=alice") == nil)
    }

    @Test
    func communityURL_missingName_returnsNil() {
        #expect(resolve("spud-markdown://community?instance=lemmy.world") == nil)
    }
}
