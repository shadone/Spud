//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import SpudUtilKit

final class URLSpudInternalLinkTests: XCTestCase {
    func test_objectAtURL_roundTrips() throws {
        let canonical = try XCTUnwrap(URL(string: "https://lemmy.world/post/123"))
        let link = URL.SpudInternalLink.objectAtURL(url: canonical)
        guard case let .objectAtURL(parsed)? = link.url.spud else {
            return XCTFail("expected .objectAtURL, got \(String(describing: link.url.spud))")
        }
        XCTAssertEqual(parsed, canonical)
    }

    func test_instance_roundTrips() throws {
        let instance = try XCTUnwrap(InstanceActorId(from: "https://beehaw.org"))
        let link = URL.SpudInternalLink.instance(instance: instance)
        guard case let .instance(parsed)? = link.url.spud else {
            return XCTFail("expected .instance, got \(String(describing: link.url.spud))")
        }
        XCTAssertEqual(parsed, instance)
    }

    func test_existingPostCase_stillParses() throws {
        let instance = try XCTUnwrap(InstanceActorId(from: "https://lemmy.world"))
        let link = URL.SpudInternalLink.post(postId: 42, instance: instance)
        guard case let .post(postId, parsedInstance)? = link.url.spud else {
            return XCTFail("expected .post")
        }
        XCTAssertEqual(postId, 42)
        XCTAssertEqual(parsedInstance, instance)
    }
}
