//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import XCTest
@testable import SpudUtilKit

class InstanceActorIdTests: XCTestCase {
    func test_string_invalid() throws {
        XCTAssertNil(InstanceActorId(from: ""))
        XCTAssertNil(InstanceActorId(from: "mkyong,com"))
    }

    func test_string_valid() throws {
        XCTAssertEqual(
            InstanceActorId(from: "www.google.com")?.actorId,
            "https://www.google.com"
        )
        XCTAssertEqual(
            InstanceActorId(from: "google.com")?.actorId,
            "https://google.com"
        )
        XCTAssertEqual(
            InstanceActorId(from: "mkyong123.com")?.actorId,
            "https://mkyong123.com"
        )
        XCTAssertEqual(
            InstanceActorId(from: "mkyong-info.com")?.actorId,
            "https://mkyong-info.com"
        )
        XCTAssertEqual(
            InstanceActorId(from: "sub.mkyong.com")?.actorId,
            "https://sub.mkyong.com"
        )
        XCTAssertEqual(
            InstanceActorId(from: "sub.mkyong-info.com")?.actorId,
            "https://sub.mkyong-info.com"
        )
        XCTAssertEqual(
            InstanceActorId(from: "mkyong.com.au")?.actorId,
            "https://mkyong.com.au"
        )
        XCTAssertEqual(
            InstanceActorId(from: "g.co")?.actorId,
            "https://g.co"
        )
        XCTAssertEqual(
            InstanceActorId(from: "mkyong.t.t.co")?.actorId,
            "https://mkyong.t.t.co"
        )
    }

    func test_string_simple() throws {
        let foobar = InstanceActorId(from: "foobar.com")
        XCTAssertNotNil(foobar)
        XCTAssertEqual(foobar?.host, "foobar.com")
        XCTAssertNil(foobar?.port)
        XCTAssertEqual(foobar?.actorId, "https://foobar.com")

        let caseSensitive = InstanceActorId(from: "FoObAr.CoM")
        XCTAssertNotNil(caseSensitive)
        XCTAssertEqual(caseSensitive?.host, "foobar.com")
        XCTAssertNil(caseSensitive?.port)
        XCTAssertEqual(caseSensitive?.actorId, "https://foobar.com")
    }

    func test_string_scheme() throws {
        let foobar = InstanceActorId(from: "https://foobar.com")
        XCTAssertNotNil(foobar)
        XCTAssertEqual(foobar?.host, "foobar.com")
        XCTAssertNil(foobar?.port)
        XCTAssertEqual(foobar?.actorId, "https://foobar.com")
    }

    func test_string_port() throws {
        let foobar = InstanceActorId(from: "foobar.com:8080")
        XCTAssertNotNil(foobar)
        XCTAssertEqual(foobar?.host, "foobar.com")
        XCTAssertEqual(foobar?.port, 8080)
        XCTAssertEqual(foobar?.actorId, "https://foobar.com:8080")
    }

    func test_string_schemeAndPort() throws {
        let foobar = InstanceActorId(from: "https://foobar.com:8080")
        XCTAssertNotNil(foobar)
        XCTAssertEqual(foobar?.host, "foobar.com")
        XCTAssertEqual(foobar?.port, 8080)
        XCTAssertEqual(foobar?.actorId, "https://foobar.com:8080")
    }

    func test_url_invalid() throws {
        XCTAssertNil(InstanceActorId(from: URL(string: "https://")!))
    }

    func test_url() throws {
        let foobar = InstanceActorId(from: URL(string: "https://foobar.com")!)
        XCTAssertNotNil(foobar)
        XCTAssertEqual(foobar?.host, "foobar.com")
        XCTAssertNil(foobar?.port)
        XCTAssertEqual(foobar?.actorId, "https://foobar.com")

        let caseSensitive = InstanceActorId(from: URL(string: "https://FoObAr.CoM")!)
        XCTAssertNotNil(caseSensitive)
        XCTAssertEqual(caseSensitive?.host, "foobar.com")
        XCTAssertNil(caseSensitive?.port)
        XCTAssertEqual(caseSensitive?.actorId, "https://foobar.com")
    }

    func test_url_port() throws {
        let foobar = InstanceActorId(from: URL(string: "https://foobar.com:8080")!)
        XCTAssertNotNil(foobar)
        XCTAssertEqual(foobar?.host, "foobar.com")
        XCTAssertEqual(foobar?.port, 8080)
        XCTAssertEqual(foobar?.actorId, "https://foobar.com:8080")
    }
}
