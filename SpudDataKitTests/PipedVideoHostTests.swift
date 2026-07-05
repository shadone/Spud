//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUtilKit
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

struct PipedInstanceResolverTests {
    /// A config whose YouTube front-end is the cataloged Piped instance, enabled.
    private var pipedFrontEnd: URLSanitizerConfig {
        var c = URLSanitizerConfig.default
        c.redirectToFrontEnds = true
        c.frontEnds = c.frontEnds.map {
            $0.service == .youtube ? FrontEndConfig(service: .youtube, isEnabled: true, host: "piped.video") : $0
        }
        return c
    }

    private func apiHost(_ urlString: String, _ config: URLSanitizerConfig) -> String? {
        PipedInstanceResolver.apiHost(forYouTubePageURL: URL(string: urlString)!, config: config)
    }

    @Test
    func pipedVideoUrlUsesCatalogApiHost() {
        #expect(apiHost("https://piped.video/watch?v=dQw4w9WgXcQ", .default) == "pipedapi.kavin.rocks")
    }

    @Test
    func youtubeUrlUsesUsersPipedFrontEnd() {
        #expect(apiHost("https://www.youtube.com/watch?v=dQw4w9WgXcQ", pipedFrontEnd) == "pipedapi.kavin.rocks")
    }

    @Test
    func youtubeUrlIsNilWhenFrontEndNotPiped() {
        // Default: redirectToFrontEnds off -> no Piped instance for a raw youtube link.
        #expect(apiHost("https://www.youtube.com/watch?v=dQw4w9WgXcQ", .default) == nil)
    }

    @Test
    func nonYoutubeUrlIsNil() {
        #expect(apiHost("https://example.com/article", .default) == nil)
    }
}
