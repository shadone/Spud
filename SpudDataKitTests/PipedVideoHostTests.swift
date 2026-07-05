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

struct PipedVideoHostRecognitionTests {
    private let host = PipedVideoHost()

    private func match(_ s: String) -> VideoHostMatch? {
        host.recognize(URL(string: s)!)
    }

    @Test
    func recognizesCanonicalYouTube() {
        #expect(match("https://www.youtube.com/watch?v=dQw4w9WgXcQ")?.identifier == "dQw4w9WgXcQ")
        #expect(match("https://youtu.be/dQw4w9WgXcQ")?.identifier == "dQw4w9WgXcQ")
        #expect(match("https://www.youtube.com/watch?v=dQw4w9WgXcQ")?.kind == .piped)
    }

    @Test
    func recognizesPipedVideo() {
        #expect(match("https://piped.video/watch?v=dQw4w9WgXcQ")?.identifier == "dQw4w9WgXcQ")
    }

    @Test
    func doesNotClaimInvidiousOrNonVideo() {
        #expect(match("https://yewtu.be/watch?v=dQw4w9WgXcQ") == nil)
        #expect(match("https://example.com/article") == nil)
    }
}

struct PipedVideoHostResolutionTests {
    private func host(returning json: String?, config: URLSanitizerConfig) -> PipedVideoHost {
        PipedVideoHost(fetch: { _ in json.map { Data($0.utf8) } }, config: config)
    }

    private var pipedConfig: URLSanitizerConfig {
        var c = URLSanitizerConfig.default
        c.redirectToFrontEnds = true
        c.frontEnds = c.frontEnds.map {
            $0.service == .youtube ? FrontEndConfig(service: .youtube, isEnabled: true, host: "piped.video") : $0
        }
        return c
    }

    private let ytMatch = VideoHostMatch(
        kind: .piped,
        identifier: "dQw4w9WgXcQ",
        pageUrl: URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!
    )

    @Test
    func prefersHlsMasterPlaylist() async throws {
        let json = """
            {"title":"Song","thumbnailUrl":"https://pipedproxy.kavin.rocks/thumb.jpg",\
            "hls":"https://pipedproxy.kavin.rocks/hls/master.m3u8","proxyUrl":"https://pipedproxy.kavin.rocks",\
            "videoStreams":[{"url":"https://x.googlevideo.com/v?id=1","videoOnly":false,"bitrate":500}]}
            """
        let resolved = try await host(returning: json, config: pipedConfig).resolve(ytMatch)
        #expect(resolved.streamUrl.absoluteString == "https://pipedproxy.kavin.rocks/hls/master.m3u8")
        #expect(resolved.title == "Song")
    }

    @Test
    func proxiesHighestBitrateProgressiveWhenNoHls() async throws {
        let json = """
            {"proxyUrl":"https://pipedproxy.kavin.rocks",\
            "videoStreams":[{"url":"https://rr1.googlevideo.com/videoplayback?id=lo","videoOnly":false,"bitrate":300},\
            {"url":"https://rr2.googlevideo.com/videoplayback?id=hi","videoOnly":false,"bitrate":800}]}
            """
        let resolved = try await host(returning: json, config: pipedConfig).resolve(ytMatch)
        // Highest bitrate, proxied — the connection host must be the proxy, never googlevideo.
        #expect(resolved.streamUrl.host == "pipedproxy.kavin.rocks")
        #expect(resolved.streamUrl.absoluteString.contains("id=hi"))
    }

    @Test
    func refusesWhenOnlyAdaptiveStreams() async {
        let json = #"{"proxyUrl":"https://pipedproxy.kavin.rocks","videoStreams":[{"url":"https://x.googlevideo.com/v","videoOnly":true,"bitrate":900}]}"#
        await #expect(throws: VideoHostResolutionError.noPlayableFile) {
            try await host(returning: json, config: pipedConfig).resolve(ytMatch)
        }
    }

    @Test
    func refusesWhenNoProxyUrl() async {
        let json = #"{"videoStreams":[{"url":"https://x.googlevideo.com/v","videoOnly":false,"bitrate":500}]}"#
        await #expect(throws: VideoHostResolutionError.noPlayableFile) {
            try await host(returning: json, config: pipedConfig).resolve(ytMatch)
        }
    }

    @Test
    func unresolvableWhenFrontEndNotPiped() async {
        await #expect(throws: VideoHostResolutionError.unresolvable) {
            try await host(returning: #"{"hls":"https://p/hls.m3u8"}"#, config: .default).resolve(ytMatch)
        }
    }

    @Test
    func networkErrorWhenFetchNil() async {
        await #expect(throws: VideoHostResolutionError.network) {
            try await host(returning: nil, config: pipedConfig).resolve(ytMatch)
        }
    }
}
