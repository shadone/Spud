//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudDataKit

struct LoopsVideoHostRecognitionTests {
    private let host = LoopsVideoHost()

    private func match(_ string: String) -> VideoHostMatch? {
        host.recognize(URL(string: string)!)
    }

    @Test
    func recognizesShareUrl() {
        let m = match("https://loops.video/v/gLbKEGRkoA")
        #expect(m?.kind == .loops)
        #expect(m?.identifier == "gLbKEGRkoA")
        #expect(m?.pageUrl.absoluteString == "https://loops.video/v/gLbKEGRkoA")
    }

    @Test
    func recognizesWwwHost() {
        #expect(match("https://www.loops.video/v/gLbKEGRkoA")?.identifier == "gLbKEGRkoA")
    }

    @Test
    func ignoresQueryAndTrailingSlash() {
        #expect(match("https://loops.video/v/gLbKEGRkoA?t=2")?.identifier == "gLbKEGRkoA")
        #expect(match("https://loops.video/v/gLbKEGRkoA/")?.identifier == "gLbKEGRkoA")
    }

    @Test
    func rejectsProfilesEmbedsAndBadShapes() {
        #expect(match("https://loops.video/@user") == nil)
        #expect(match("https://loops.video/") == nil)
        #expect(match("https://loops.video/embed/gLbKEGRkoA") == nil)
        #expect(match("https://loops.video/v/gLbKEGRkoA/extra") == nil)
        #expect(match("https://example.com/v/gLbKEGRkoA") == nil)
    }

    @Test
    func rejectsUndecodableShortcode() {
        // 11 characters — a valid-alphabet but over-length shortcode does not decode,
        // so the URL classifies as an external link rather than a dead inline video.
        #expect(match("https://loops.video/v/aaaaaaaaaaa") == nil)
    }
}

struct LoopsVideoHostResolutionTests {
    private func host(returning json: String?) -> LoopsVideoHost {
        LoopsVideoHost(fetch: { _ in json.map { Data($0.utf8) } })
    }

    private let match = VideoHostMatch(
        kind: .loops,
        identifier: "gLbKEGRkoA",
        pageUrl: URL(string: "https://loops.video/v/gLbKEGRkoA")!
    )

    @Test
    func resolvesToSrcUrlWithPosterAndTitle() async throws {
        let json = """
            {"caption":"A clip","media":{"src_url":"https://cdn.loops.video/v/abc.mp4",\
            "hls_url":null,"thumbnail":"https://cdn.loops.video/t/abc.jpg"}}
            """
        let resolved = try await host(returning: json).resolve(match)
        #expect(resolved.streamUrl.absoluteString == "https://cdn.loops.video/v/abc.mp4")
        #expect(resolved.posterUrl?.absoluteString == "https://cdn.loops.video/t/abc.jpg")
        #expect(resolved.title == "A clip")
    }

    @Test
    func prefersHlsUrlOverSrcUrl() async throws {
        let json = """
            {"caption":"c","media":{"src_url":"https://cdn.loops.video/v/abc.mp4",\
            "hls_url":"https://cdn.loops.video/h/abc.m3u8","thumbnail":null}}
            """
        let resolved = try await host(returning: json).resolve(match)
        #expect(resolved.streamUrl.absoluteString == "https://cdn.loops.video/h/abc.m3u8")
    }

    @Test
    func throwsWhenNoPlayableFile() async {
        // A still-processing video: both media URLs null.
        let json = #"{"caption":"c","media":{"src_url":null,"hls_url":null,"thumbnail":null}}"#
        await #expect(throws: VideoHostResolutionError.noPlayableFile) {
            try await host(returning: json).resolve(match)
        }
    }

    @Test
    func throwsOnNetworkFailure() async {
        await #expect(throws: VideoHostResolutionError.network) {
            try await host(returning: nil).resolve(match)
        }
    }

    @Test
    func throwsDecodingOnMalformedJson() async {
        await #expect(throws: VideoHostResolutionError.decoding) {
            try await host(returning: "not json").resolve(match)
        }
    }
}
