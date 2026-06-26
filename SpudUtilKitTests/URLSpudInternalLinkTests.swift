//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Testing
@testable import SpudUtilKit

struct URLSpudInternalLinkTests {
    @Test
    func objectAtURL_roundTrips() throws {
        let canonical = try #require(URL(string: "https://lemmy.world/post/123"))
        let link = URL.SpudInternalLink.objectAtURL(url: canonical)
        guard case let .objectAtURL(parsed)? = link.url.spud else {
            Issue.record("expected .objectAtURL, got \(String(describing: link.url.spud))")
            return
        }
        #expect(parsed == canonical)
    }

    @Test
    func instance_roundTrips() throws {
        let instance = try #require(InstanceActorId(from: "https://beehaw.org"))
        let link = URL.SpudInternalLink.instance(instance: instance)
        guard case let .instance(parsed)? = link.url.spud else {
            Issue.record("expected .instance, got \(String(describing: link.url.spud))")
            return
        }
        #expect(parsed == instance)
    }

    /// The inner URL's `?`/`&` must survive being nested inside the outer
    /// `spud://` query string — the case most likely to break round-tripping.
    @Test
    func objectAtURL_withQueryString_roundTrips() throws {
        let canonical = try #require(URL(string: "https://beehaw.org/post/789?page=2&sort=top"))
        let link = URL.SpudInternalLink.objectAtURL(url: canonical)
        guard case let .objectAtURL(parsed)? = link.url.spud else {
            Issue.record("expected .objectAtURL, got \(String(describing: link.url.spud))")
            return
        }
        #expect(parsed == canonical)
    }

    @Test
    func post_roundTrips() throws {
        let instance = try #require(InstanceActorId(from: "https://lemmy.world"))
        let link = URL.SpudInternalLink.post(postId: 42, instance: instance)
        guard case let .post(postId, parsedInstance)? = link.url.spud else {
            Issue.record("expected .post")
            return
        }
        #expect(postId == 42)
        #expect(parsedInstance == instance)
    }
}
