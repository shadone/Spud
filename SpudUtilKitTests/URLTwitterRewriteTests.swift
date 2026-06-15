//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import XCTest
@testable import SpudUtilKit

class URLTwitterRewriteTests: XCTestCase {
    private func rewritten(_ string: String) -> String? {
        URL(string: string)?.rewritingTwitterToXcancel().absoluteString
    }

    func test_rewritesTwitterDotCom() {
        XCTAssertEqual(
            rewritten("https://twitter.com/jack/status/20"),
            "https://xcancel.com/jack/status/20"
        )
    }

    func test_rewritesXDotCom() {
        XCTAssertEqual(
            rewritten("https://x.com/jack/status/20"),
            "https://xcancel.com/jack/status/20"
        )
    }

    func test_rewritesWwwMobileAndMSubdomains() {
        XCTAssertEqual(rewritten("https://www.twitter.com/jack"), "https://xcancel.com/jack")
        XCTAssertEqual(rewritten("https://mobile.twitter.com/jack"), "https://xcancel.com/jack")
        XCTAssertEqual(rewritten("https://m.twitter.com/jack"), "https://xcancel.com/jack")
        XCTAssertEqual(rewritten("https://www.x.com/jack"), "https://xcancel.com/jack")
    }

    func test_preservesQueryAndFragment() {
        XCTAssertEqual(
            rewritten("https://twitter.com/jack/status/20?s=20&t=abc#frag"),
            "https://xcancel.com/jack/status/20?s=20&t=abc#frag"
        )
    }

    func test_isCaseInsensitiveOnHost() {
        XCTAssertEqual(rewritten("https://Twitter.com/jack"), "https://xcancel.com/jack")
        XCTAssertEqual(rewritten("https://X.COM/jack"), "https://xcancel.com/jack")
    }

    func test_leavesNonTwitterHostsUnchanged() {
        XCTAssertEqual(rewritten("https://youtu.be/0ORqQPk7kjs"), "https://youtu.be/0ORqQPk7kjs")
        XCTAssertEqual(rewritten("https://mozilla.org/x.com"), "https://mozilla.org/x.com")
    }

    func test_doesNotMatchLookalikeHosts() {
        // Hosts that merely contain "x.com" or an unlisted twitter subdomain
        // must not be rewritten.
        XCTAssertEqual(rewritten("https://netflix.com/title"), "https://netflix.com/title")
        XCTAssertEqual(rewritten("https://api.twitter.com/2/tweets"), "https://api.twitter.com/2/tweets")
        XCTAssertEqual(rewritten("https://notx.com/jack"), "https://notx.com/jack")
    }

    func test_leavesAlreadyXcancelUnchanged() {
        XCTAssertEqual(rewritten("https://xcancel.com/jack"), "https://xcancel.com/jack")
    }

    func test_returnsSelfWhenNoHost() {
        XCTAssertEqual(rewritten("mailto:jack@twitter.com"), "mailto:jack@twitter.com")
    }
}
