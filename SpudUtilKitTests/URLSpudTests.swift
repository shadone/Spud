//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudUtilKit

struct URLSpudTests {
    // MARK: - Post

    @Test
    func parsePost_noScheme() throws {
        let post = try #require(URL(string: "info.ddenis.spud://internal/post?postId=123&instance=example.com"))
        switch post.spud {
        case let .post(postId, instance):
            #expect(postId == 123)
            #expect(instance.actorId == "https://example.com")

        default:
            Issue.record()
        }
    }

    @Test
    func parsePost_scheme() throws {
        let post = try #require(URL(string: "info.ddenis.spud://internal/post?postId=123&instance=https://example.com"))
        switch post.spud {
        case let .post(postId, instance):
            #expect(postId == 123)
            #expect(instance.actorId == "https://example.com")

        default:
            Issue.record()
        }
    }

    @Test
    func parsePost_schemeUrlEncoded() throws {
        let post = try #require(URL(string: "info.ddenis.spud://internal/post?postId=123&instance=https%3A%2F%2Fexample.com"))
        switch post.spud {
        case let .post(postId, instance):
            #expect(postId == 123)
            #expect(instance.actorId == "https://example.com")

        default:
            Issue.record()
        }
    }

    @Test
    func parsePost_queryParamsOrder() throws {
        let post = try #require(URL(string: "info.ddenis.spud://internal/post?instance=example.com&postId=123"))
        switch post.spud {
        case let .post(postId, instance):
            #expect(postId == 123)
            #expect(instance.actorId == "https://example.com")

        default:
            Issue.record()
        }
    }

    @Test
    func parsePost_invalid() {
        // invalid scheme
        #expect(URL(string: "info.ddenis.dups://internal/post?postId=123&instance=https%3A%2F%2Fexample.com")?.spud == nil)
        // invalid host
        #expect(URL(string: "info.ddenis.spud://unknownhost/post?instance=example.com&postId=123")?.spud == nil)
        // invalid path
        #expect(URL(string: "info.ddenis.spud://internal/unknownpath?instance=example.com&postId=123")?.spud == nil)
        // missing "instance" query param
        #expect(URL(string: "info.ddenis.spud://internal/post?postId=123")?.spud == nil)
        // missing "postId" query param
        #expect(URL(string: "info.ddenis.spud://internal/post?instance=example.com")?.spud == nil)
    }

    @Test
    func makePost() throws {
        let url = try URL.SpudInternalLink
            .post(postId: 123, instance: #require(.init(from: "example.com"))).url
        #expect(
            url.absoluteString ==
                "info.ddenis.spud://internal/post?postId=123&instance=https://example.com"
        )
    }

    // MARK: - Person

    @Test
    func parsePerson_noScheme() throws {
        let post = try #require(URL(string: "info.ddenis.spud://internal/person?personId=123&instance=example.com"))
        switch post.spud {
        case let .person(personId, instance):
            #expect(personId == 123)
            #expect(instance.actorId == "https://example.com")

        default:
            Issue.record()
        }
    }

    @Test
    func parsePerson_scheme() throws {
        let post = try #require(URL(string: "info.ddenis.spud://internal/person?personId=123&instance=https://example.com"))
        switch post.spud {
        case let .person(personId, instance):
            #expect(personId == 123)
            #expect(instance.actorId == "https://example.com")

        default:
            Issue.record()
        }
    }

    @Test
    func parsePerson_schemeUrlEncoded() throws {
        let post = try #require(URL(string: "info.ddenis.spud://internal/person?personId=123&instance=https%3A%2F%2Fexample.com"))
        switch post.spud {
        case let .person(personId, instance):
            #expect(personId == 123)
            #expect(instance.actorId == "https://example.com")

        default:
            Issue.record()
        }
    }

    @Test
    func parsePerson_queryParamsOrder() throws {
        let post = try #require(URL(string: "info.ddenis.spud://internal/person?instance=example.com&personId=123"))
        switch post.spud {
        case let .person(personId, instance):
            #expect(personId == 123)
            #expect(instance.actorId == "https://example.com")

        default:
            Issue.record()
        }
    }

    @Test
    func parsePerson_invalid() {
        // invalid scheme
        #expect(URL(string: "info.ddenis.dups://internal/person?personId=123&instance=https%3A%2F%2Fexample.com")?.spud == nil)
        // invalid host
        #expect(URL(string: "info.ddenis.spud://unknownhost/person?instance=example.com&personId=123")?.spud == nil)
        // invalid path
        #expect(URL(string: "info.ddenis.spud://internal/unknownpath?instance=example.com&personId=123")?.spud == nil)
        // missing "instance" query param
        #expect(URL(string: "info.ddenis.spud://internal/person?personId=123")?.spud == nil)
        // missing "postId" query param
        #expect(URL(string: "info.ddenis.spud://internal/person?instance=example.com")?.spud == nil)
    }

    @Test
    func makePerson() throws {
        let url = try URL.SpudInternalLink
            .person(personId: 123, instance: #require(.init(from: "example.com"))).url
        #expect(
            url.absoluteString ==
                "info.ddenis.spud://internal/person?personId=123&instance=https://example.com"
        )
    }
}
