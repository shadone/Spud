//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUtilKit
import Testing
@testable import Spud

struct SearchURLDetectorTests {
    private let known: (String) -> Bool = { ["lemmy.world", "beehaw.org"].contains($0) }

    private func detect(_ s: String) -> SearchURLSuggestion? {
        SearchURLDetector.detect(query: s, isKnownInstance: known)
    }

    // MARK: Known instance: classify drives kind + link.

    @Test
    func knownPost_isPostKind_objectAtURL() throws {
        let s = try #require(detect("https://lemmy.world/post/123"))
        #expect(s.kind == .post)
        guard case let .objectAtURL(url) = s.link else { Issue.record("expected .objectAtURL")
            return
        }
        #expect(url.absoluteString == "https://lemmy.world/post/123")
    }

    @Test
    func knownComment_isCommentKind() throws {
        let s = try #require(detect("https://lemmy.world/comment/9"))
        #expect(s.kind == .comment)
        guard case .objectAtURL = s.link else { Issue.record("expected .objectAtURL")
            return
        }
    }

    @Test
    func knownUser_isUserKind() throws {
        let s = try #require(detect("https://beehaw.org/u/alice"))
        #expect(s.kind == .user)
    }

    @Test
    func knownCommunity_isCommunityKind_communityLink() throws {
        let s = try #require(detect("https://lemmy.world/c/technology"))
        #expect(s.kind == .community)
        guard case let .community(name, instance) = s.link else { Issue.record("expected .community")
            return
        }
        #expect(name == "technology")
        #expect(instance.host == "lemmy.world")
    }

    @Test
    func bareKnownInstance_isInstanceKind() throws {
        let s = try #require(detect("https://beehaw.org"))
        #expect(s.kind == .instance)
        guard case .instance = s.link else { Issue.record("expected .instance")
            return
        }
    }

    // MARK: Unknown host: path-shape fallback -> objectAtURL with derived kind.

    @Test
    func unknownPost_isOffered_objectAtURL() throws {
        let s = try #require(detect("https://small.example/post/1"))
        #expect(s.kind == .post)
        guard case let .objectAtURL(url) = s.link else { Issue.record("expected .objectAtURL")
            return
        }
        #expect(url.absoluteString == "https://small.example/post/1")
    }

    @Test
    func unknownComment_isOffered() throws {
        let s = try #require(detect("https://small.example/comment/7"))
        #expect(s.kind == .comment)
    }

    @Test
    func unknownUser_isOffered() throws {
        let s = try #require(detect("https://small.example/u/bob"))
        #expect(s.kind == .user)
    }

    @Test
    func unknownCommunity_isOffered_objectAtURL() throws {
        let s = try #require(detect("https://small.example/c/games"))
        #expect(s.kind == .community)
        guard case .objectAtURL = s.link else { Issue.record("expected .objectAtURL for unknown host")
            return
        }
    }

    @Test
    func knownCommunity_qualifiedName_usesQualifiedHost() throws {
        let s = try #require(detect("https://lemmy.world/c/games@beehaw.org"))
        #expect(s.kind == .community)
        guard case let .community(name, instance) = s.link else { Issue.record("expected .community")
            return
        }
        #expect(name == "games")
        #expect(instance.host == "beehaw.org")
    }

    // MARK: Frontend post URL (/c/<community>/p/<id>[/<slug>]).

    @Test
    func unknownFrontendPost_isOffered_canonicalObjectAtURL() throws {
        // The reported case: a frontend post URL on an unknown instance.
        let s = try #require(detect("https://feddit.online/c/opensource/p/1784296/favorite-open-source-game"))
        #expect(s.kind == .post)
        guard case let .objectAtURL(url) = s.link else { Issue.record("expected .objectAtURL")
            return
        }
        #expect(url.absoluteString == "https://feddit.online/post/1784296")
        // The row still shows what the user pasted.
        #expect(s.displayURL == "feddit.online/c/opensource/p/1784296/favorite-open-source-game")
    }

    @Test
    func knownFrontendPost_isOffered() throws {
        let s = try #require(detect("https://lemmy.world/c/opensource/p/42"))
        #expect(s.kind == .post)
        guard case let .objectAtURL(url) = s.link else { Issue.record("expected .objectAtURL")
            return
        }
        #expect(url.absoluteString == "https://lemmy.world/post/42")
    }

    @Test
    func frontendPost_nonNumericId_isNil() {
        #expect(detect("https://feddit.online/c/opensource/p/abc/slug") == nil)
    }

    // MARK: Negatives.

    @Test
    func bareUnknownHost_isNil() {
        #expect(detect("https://example.com") == nil)
    }

    @Test
    func plainText_isNil() {
        #expect(detect("cats") == nil)
        #expect(detect("how to make pasta") == nil)
    }

    @Test
    func nonHttpScheme_isNil() {
        #expect(detect("mailto:a@b.com") == nil)
        #expect(detect("info.ddenis.spud://internal/post?postId=1&instance=x") == nil)
    }

    @Test
    func unknownNonLemmyPath_isNil() {
        #expect(detect("https://news.example/article/abc") == nil)
    }

    @Test
    func postWithNonNumericId_isNil() {
        #expect(detect("https://small.example/post/notanumber") == nil)
    }

    @Test
    func displayURL_dropsScheme() throws {
        let s = try #require(detect("https://lemmy.world/post/123"))
        #expect(s.displayURL == "lemmy.world/post/123")
    }

    @Test
    func whitespaceIsTrimmed() throws {
        let s = try #require(detect("  https://lemmy.world/post/123  "))
        #expect(s.kind == .post)
    }
}
