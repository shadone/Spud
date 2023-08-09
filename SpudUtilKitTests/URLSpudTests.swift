//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import XCTest
@testable import SpudUtilKit

class URLSpudTests: XCTestCase {
    // MARK: - Post

    func test_parsePost_noScheme() throws {
        let post = URL(string: "info.ddenis.spud://internal/post?postId=123&instance=example.com")!
        switch post.spud {
        case let .post(postId, instance):
            XCTAssertEqual(postId, 123)
            XCTAssertEqual(instance.actorId, "https://example.com")

        default:
            XCTFail()
        }
    }

    func test_parsePost_scheme() throws {
        let post = URL(string: "info.ddenis.spud://internal/post?postId=123&instance=https://example.com")!
        switch post.spud {
        case let .post(postId, instance):
            XCTAssertEqual(postId, 123)
            XCTAssertEqual(instance.actorId, "https://example.com")

        default:
            XCTFail()
        }
    }

    func test_parsePost_schemeUrlEncoded() throws {
        let post = URL(string: "info.ddenis.spud://internal/post?postId=123&instance=https%3A%2F%2Fexample.com")!
        switch post.spud {
        case let .post(postId, instance):
            XCTAssertEqual(postId, 123)
            XCTAssertEqual(instance.actorId, "https://example.com")

        default:
            XCTFail()
        }
    }

    func test_parsePost_queryParamsOrder() throws {
        let post = URL(string: "info.ddenis.spud://internal/post?instance=example.com&postId=123")!
        switch post.spud {
        case let .post(postId, instance):
            XCTAssertEqual(postId, 123)
            XCTAssertEqual(instance.actorId, "https://example.com")

        default:
            XCTFail()
        }
    }

    func test_parsePost_invalid() throws {
        // invalid scheme
        XCTAssertNil(URL(string: "info.ddenis.dups://internal/post?postId=123&instance=https%3A%2F%2Fexample.com")!.spud)
        // invalid host
        XCTAssertNil(URL(string: "info.ddenis.spud://unknownhost/post?instance=example.com&postId=123")!.spud)
        // invalid path
        XCTAssertNil(URL(string: "info.ddenis.spud://internal/unknownpath?instance=example.com&postId=123")!.spud)
        // missing "instance" query param
        XCTAssertNil(URL(string: "info.ddenis.spud://internal/post?postId=123")!.spud)
        // missing "postId" query param
        XCTAssertNil(URL(string: "info.ddenis.spud://internal/post?instance=example.com")!.spud)
    }

    func test_makePost() throws {
        let url = URL.SpudInternalLink
            .post(postId: 123, instance: .init(from: "example.com")!).url
        XCTAssertEqual(
            url.absoluteString,
            "info.ddenis.spud://internal/post?postId=123&instance=https://example.com"
        )
    }

    // MARK: - Person

    func test_parsePerson_noScheme() throws {
        let post = URL(string: "info.ddenis.spud://internal/person?personId=123&instance=example.com")!
        switch post.spud {
        case let .person(personId, instance):
            XCTAssertEqual(personId, 123)
            XCTAssertEqual(instance.actorId, "https://example.com")

        default:
            XCTFail()
        }
    }

    func test_parsePerson_scheme() throws {
        let post = URL(string: "info.ddenis.spud://internal/person?personId=123&instance=https://example.com")!
        switch post.spud {
        case let .person(personId, instance):
            XCTAssertEqual(personId, 123)
            XCTAssertEqual(instance.actorId, "https://example.com")

        default:
            XCTFail()
        }
    }

    func test_parsePerson_schemeUrlEncoded() throws {
        let post = URL(string: "info.ddenis.spud://internal/person?personId=123&instance=https%3A%2F%2Fexample.com")!
        switch post.spud {
        case let .person(personId, instance):
            XCTAssertEqual(personId, 123)
            XCTAssertEqual(instance.actorId, "https://example.com")

        default:
            XCTFail()
        }
    }

    func test_parsePerson_queryParamsOrder() throws {
        let post = URL(string: "info.ddenis.spud://internal/person?instance=example.com&personId=123")!
        switch post.spud {
        case let .person(personId, instance):
            XCTAssertEqual(personId, 123)
            XCTAssertEqual(instance.actorId, "https://example.com")

        default:
            XCTFail()
        }
    }

    func test_parsePerson_invalid() throws {
        // invalid scheme
        XCTAssertNil(URL(string: "info.ddenis.dups://internal/person?personId=123&instance=https%3A%2F%2Fexample.com")!.spud)
        // invalid host
        XCTAssertNil(URL(string: "info.ddenis.spud://unknownhost/person?instance=example.com&personId=123")!.spud)
        // invalid path
        XCTAssertNil(URL(string: "info.ddenis.spud://internal/unknownpath?instance=example.com&personId=123")!.spud)
        // missing "instance" query param
        XCTAssertNil(URL(string: "info.ddenis.spud://internal/person?personId=123")!.spud)
        // missing "postId" query param
        XCTAssertNil(URL(string: "info.ddenis.spud://internal/person?instance=example.com")!.spud)
    }

    func test_makePerson() throws {
        let url = URL.SpudInternalLink
            .person(personId: 123, instance: .init(from: "example.com")!).url
        XCTAssertEqual(
            url.absoluteString,
            "info.ddenis.spud://internal/person?personId=123&instance=https://example.com"
        )
    }
}
