//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudUtilKit

struct InstanceActorIdTests {
    @Test
    func string_invalid() {
        #expect(InstanceActorId(from: "") == nil)
        #expect(InstanceActorId(from: "mkyong,com") == nil)
    }

    @Test
    func string_valid() {
        #expect(
            InstanceActorId(from: "www.google.com")?.actorId ==
                "https://www.google.com"
        )
        #expect(
            InstanceActorId(from: "google.com")?.actorId ==
                "https://google.com"
        )
        #expect(
            InstanceActorId(from: "mkyong123.com")?.actorId ==
                "https://mkyong123.com"
        )
        #expect(
            InstanceActorId(from: "mkyong-info.com")?.actorId ==
                "https://mkyong-info.com"
        )
        #expect(
            InstanceActorId(from: "sub.mkyong.com")?.actorId ==
                "https://sub.mkyong.com"
        )
        #expect(
            InstanceActorId(from: "sub.mkyong-info.com")?.actorId ==
                "https://sub.mkyong-info.com"
        )
        #expect(
            InstanceActorId(from: "mkyong.com.au")?.actorId ==
                "https://mkyong.com.au"
        )
        #expect(
            InstanceActorId(from: "g.co")?.actorId ==
                "https://g.co"
        )
        #expect(
            InstanceActorId(from: "mkyong.t.t.co")?.actorId ==
                "https://mkyong.t.t.co"
        )
    }

    @Test
    func string_simple() {
        let foobar = InstanceActorId(from: "foobar.com")
        #expect(foobar != nil)
        #expect(foobar?.host == "foobar.com")
        #expect(foobar?.port == nil)
        #expect(foobar?.actorId == "https://foobar.com")

        let caseSensitive = InstanceActorId(from: "FoObAr.CoM")
        #expect(caseSensitive != nil)
        #expect(caseSensitive?.host == "foobar.com")
        #expect(caseSensitive?.port == nil)
        #expect(caseSensitive?.actorId == "https://foobar.com")
    }

    @Test
    func string_scheme() {
        let foobar = InstanceActorId(from: "https://foobar.com")
        #expect(foobar != nil)
        #expect(foobar?.host == "foobar.com")
        #expect(foobar?.port == nil)
        #expect(foobar?.actorId == "https://foobar.com")
    }

    @Test
    func string_port() {
        let foobar = InstanceActorId(from: "foobar.com:8080")
        #expect(foobar != nil)
        #expect(foobar?.host == "foobar.com")
        #expect(foobar?.port == 8080)
        #expect(foobar?.actorId == "https://foobar.com:8080")
    }

    @Test
    func string_schemeAndPort() {
        let foobar = InstanceActorId(from: "https://foobar.com:8080")
        #expect(foobar != nil)
        #expect(foobar?.host == "foobar.com")
        #expect(foobar?.port == 8080)
        #expect(foobar?.actorId == "https://foobar.com:8080")
    }

    @Test
    func url_invalid() throws {
        #expect(try InstanceActorId(from: #require(URL(string: "https://"))) == nil)
    }

    @Test
    func url() throws {
        let foobar = try InstanceActorId(from: #require(URL(string: "https://foobar.com")))
        #expect(foobar != nil)
        #expect(foobar?.host == "foobar.com")
        #expect(foobar?.port == nil)
        #expect(foobar?.actorId == "https://foobar.com")

        let caseSensitive = try InstanceActorId(from: #require(URL(string: "https://FoObAr.CoM")))
        #expect(caseSensitive != nil)
        #expect(caseSensitive?.host == "foobar.com")
        #expect(caseSensitive?.port == nil)
        #expect(caseSensitive?.actorId == "https://foobar.com")
    }

    @Test
    func url_port() throws {
        let foobar = try InstanceActorId(from: #require(URL(string: "https://foobar.com:8080")))
        #expect(foobar != nil)
        #expect(foobar?.host == "foobar.com")
        #expect(foobar?.port == 8080)
        #expect(foobar?.actorId == "https://foobar.com:8080")
    }
}
