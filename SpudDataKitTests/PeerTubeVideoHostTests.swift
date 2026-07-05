//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudDataKit

struct PeerTubeVideoHostRecognitionTests {
    private let host = PeerTubeVideoHost()

    private func match(_ string: String) -> VideoHostMatch? {
        host.recognize(URL(string: string)!)
    }

    @Test
    func recognizesShortWatchForm() {
        let m = match("https://tube.example/w/kR2p9qXy")
        #expect(m?.kind == .peertube)
        #expect(m?.identifier == "kR2p9qXy")
        #expect(m?.pageUrl.absoluteString == "https://tube.example/w/kR2p9qXy")
    }

    @Test
    func recognizesLongWatchUuidForm() {
        let uuid = "0e3c8d2a-1234-4abc-9def-0123456789ab"
        #expect(match("https://tube.example/videos/watch/\(uuid)")?.identifier == uuid)
    }

    @Test
    func doesNotClaimYouTube() {
        #expect(match("https://www.youtube.com/watch?v=dQw4w9WgXcQ") == nil)
    }

    @Test
    func rejectsNonVideoUrls() {
        #expect(match("https://example.com/some/article") == nil)
        // too short for VideoLinkParser's PeerTube heuristic
        #expect(match("https://tube.example/w/abc") == nil)
    }
}

private actor URLBox {
    var url: URL?
    func set(_ u: URL) {
        url = u
    }
}

struct PeerTubeVideoHostResolutionTests {
    private func host(returning json: String?) -> PeerTubeVideoHost {
        PeerTubeVideoHost(fetch: { _ in json.map { Data($0.utf8) } })
    }

    private let match = VideoHostMatch(
        kind: .peertube,
        identifier: "kR2p9qXy",
        pageUrl: URL(string: "https://tube.example/w/kR2p9qXy")!
    )

    @Test
    func picksHighestResolutionProgressiveFile() async throws {
        let json = """
            {"name":"Clip","previewPath":"/static/previews/x.jpg",\
            "files":[{"fileUrl":"https://tube.example/static/720.mp4","resolution":{"id":720}},\
            {"fileUrl":"https://tube.example/static/1080.mp4","resolution":{"id":1080}}]}
            """
        let resolved = try await host(returning: json).resolve(match)
        #expect(resolved.streamUrl.absoluteString == "https://tube.example/static/1080.mp4")
        #expect(resolved.posterUrl?.absoluteString == "https://tube.example/static/previews/x.jpg")
        #expect(resolved.title == "Clip")
    }

    @Test
    func fallsBackToHlsPlaylistWhenNoProgressiveFiles() async throws {
        let json = """
            {"name":"HLS","files":[],\
            "streamingPlaylists":[{"playlistUrl":"https://tube.example/static/hls/master.m3u8","files":[]}]}
            """
        let resolved = try await host(returning: json).resolve(match)
        #expect(resolved.streamUrl.absoluteString == "https://tube.example/static/hls/master.m3u8")
    }

    @Test
    func prefersHlsPlaylistOverNestedFragments() async throws {
        // No top-level progressive files; the nested files are HLS fragments, so
        // the master playlist must win, not a fragment fileUrl.
        let json = """
            {"files":[],"streamingPlaylists":[{"playlistUrl":"https://tube.example/hls/master.m3u8",\
            "files":[{"fileUrl":"https://tube.example/hls/1080-fragmented.mp4","resolution":{"id":1080}}]}]}
            """
        let resolved = try await host(returning: json).resolve(match)
        #expect(resolved.streamUrl.absoluteString == "https://tube.example/hls/master.m3u8")
    }

    @Test
    func prefersTopLevelProgressiveOverHls() async throws {
        let json = """
            {"files":[{"fileUrl":"https://tube.example/static/1080.mp4","resolution":{"id":1080}}],\
            "streamingPlaylists":[{"playlistUrl":"https://tube.example/hls/master.m3u8"}]}
            """
        let resolved = try await host(returning: json).resolve(match)
        #expect(resolved.streamUrl.absoluteString == "https://tube.example/static/1080.mp4")
    }

    @Test
    func throwsNetworkWhenFetchReturnsNil() async {
        await #expect(throws: VideoHostResolutionError.network) {
            try await host(returning: nil).resolve(match)
        }
    }

    @Test
    func throwsDecodingOnGarbage() async {
        await #expect(throws: VideoHostResolutionError.decoding) {
            try await host(returning: "not json").resolve(match)
        }
    }

    @Test
    func throwsNoPlayableFileWhenEmpty() async {
        let json = #"{"name":"empty","files":[],"streamingPlaylists":[]}"#
        await #expect(throws: VideoHostResolutionError.noPlayableFile) {
            try await host(returning: json).resolve(match)
        }
    }

    @Test
    func buildsApiUrlFromInstanceHostAndIdentifier() async throws {
        let box = URLBox()
        let json = #"{"files":[{"fileUrl":"https://tube.example/v.mp4","resolution":{"id":720}}]}"#
        let host = PeerTubeVideoHost(fetch: { url in
            await box.set(url)
            return Data(json.utf8)
        })
        _ = try await host.resolve(match)
        let captured = await box.url
        #expect(captured?.absoluteString == "https://tube.example/api/v1/videos/kR2p9qXy")
    }

    @Test
    func usesThumbnailPathWhenNoPreviewPath() async throws {
        let json = #"{"thumbnailPath":"/static/thumbs/t.jpg","files":[{"fileUrl":"https://tube.example/v.mp4","resolution":{"id":720}}]}"#
        let resolved = try await host(returning: json).resolve(match)
        #expect(resolved.posterUrl?.absoluteString == "https://tube.example/static/thumbs/t.jpg")
    }
}
