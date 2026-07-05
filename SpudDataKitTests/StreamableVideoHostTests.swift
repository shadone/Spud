//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudDataKit

struct StreamableVideoHostRecognitionTests {
    private let host = StreamableVideoHost()

    private func match(_ string: String) -> VideoHostMatch? {
        host.recognize(URL(string: string)!)
    }

    @Test
    func recognizesBareShortcode() {
        let m = match("https://streamable.com/67295820")
        #expect(m?.kind == .streamable)
        #expect(m?.identifier == "67295820")
        #expect(m?.pageUrl.absoluteString == "https://streamable.com/67295820")
    }

    @Test
    func recognizesWwwHost() {
        #expect(match("https://www.streamable.com/abc123")?.identifier == "abc123")
    }

    @Test
    func recognizesEmbedAndObjectForms() {
        #expect(match("https://streamable.com/e/abc123")?.identifier == "abc123")
        #expect(match("https://streamable.com/o/abc123")?.identifier == "abc123")
    }

    @Test
    func ignoresQueryAndTrailingSlash() {
        #expect(match("https://streamable.com/abc123?t=5")?.identifier == "abc123")
        #expect(match("https://streamable.com/abc123/")?.identifier == "abc123")
    }

    @Test
    func rejectsNonStreamableAndBadShapes() {
        #expect(match("https://streamable.com") == nil)
        #expect(match("https://streamable.com/abc/def") == nil)
        #expect(match("https://example.com/abc123") == nil)
        #expect(match("https://notstreamable.com/abc123") == nil)
    }
}

struct StreamableVideoHostResolutionTests {
    private func host(returning json: String?) -> StreamableVideoHost {
        StreamableVideoHost(fetch: { _ in json.map { Data($0.utf8) } })
    }

    private let match = VideoHostMatch(
        kind: .streamable,
        identifier: "abc123",
        pageUrl: URL(string: "https://streamable.com/abc123")!
    )

    @Test
    func resolvesReadyVideoToMp4WithPosterAndTitle() async throws {
        let json = """
            {"status":2,"title":"Clip","thumbnail_url":"//cdn.streamable.com/image/abc.jpg",\
            "files":{"mp4":{"url":"https://cdn.streamable.com/video/mp4/abc.mp4"},\
            "mp4-mobile":{"url":"https://cdn.streamable.com/video/mp4-mobile/abc.mp4"}}}
            """
        let resolved = try await host(returning: json).resolve(match)
        #expect(resolved.streamUrl.absoluteString == "https://cdn.streamable.com/video/mp4/abc.mp4")
        #expect(resolved.posterUrl?.absoluteString == "https://cdn.streamable.com/image/abc.jpg")
        #expect(resolved.title == "Clip")
    }

    @Test
    func normalizesProtocolRelativeStreamUrl() async throws {
        let json = #"{"status":2,"files":{"mp4":{"url":"//cdn.streamable.com/v/abc.mp4"}}}"#
        let resolved = try await host(returning: json).resolve(match)
        #expect(resolved.streamUrl.absoluteString == "https://cdn.streamable.com/v/abc.mp4")
    }

    @Test
    func fallsBackToMobileMp4() async throws {
        let json = #"{"status":2,"files":{"mp4-mobile":{"url":"https://cdn.streamable.com/m/abc.mp4"}}}"#
        let resolved = try await host(returning: json).resolve(match)
        #expect(resolved.streamUrl.absoluteString == "https://cdn.streamable.com/m/abc.mp4")
    }

    @Test
    func throwsWhenNotReady() async {
        let json = #"{"status":1,"files":{}}"#
        await #expect(throws: VideoHostResolutionError.notReady) {
            try await host(returning: json).resolve(match)
        }
    }

    @Test
    func throwsWhenNoPlayableFile() async {
        let json = #"{"status":2,"files":{}}"#
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
    func throwsDecodingWhenStatusMissing() async {
        let json = #"{"files":{"mp4":{"url":"https://cdn.streamable.com/abc.mp4"}}}"#
        await #expect(throws: VideoHostResolutionError.decoding) {
            try await host(returning: json).resolve(match)
        }
    }
}
