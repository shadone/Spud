//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudDataKit

struct PipedProxyTests {
    @Test
    func rewritesToProxyHostAndAppendsOriginalHostParam() throws {
        let stream = "https://rr3---sn-abc.googlevideo.com/videoplayback?expire=123&id=xyz"
        let proxied = try #require(PipedProxy.rewrite(streamURL: stream, proxyPrefix: "https://pipedproxy.kavin.rocks"))
        // The connection host is the proxy — never googlevideo. This IS the privacy guarantee.
        #expect(proxied.host == "pipedproxy.kavin.rocks")
        let comps = try #require(URLComponents(url: proxied, resolvingAgainstBaseURL: false))
        #expect(comps.path == "/videoplayback")
        #expect(comps.queryItems?.contains(URLQueryItem(name: "expire", value: "123")) == true)
        #expect(comps.queryItems?.contains(URLQueryItem(name: "id", value: "xyz")) == true)
        #expect(comps.queryItems?.contains(URLQueryItem(name: "host", value: "rr3---sn-abc.googlevideo.com")) == true)
    }

    @Test
    func returnsNilOnUnparseableInput() {
        #expect(PipedProxy.rewrite(streamURL: "", proxyPrefix: "https://p.host") == nil)
        #expect(PipedProxy.rewrite(streamURL: "https://x.googlevideo.com/v", proxyPrefix: "") == nil)
    }
}
