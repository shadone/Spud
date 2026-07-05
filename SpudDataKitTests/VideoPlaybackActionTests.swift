//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudDataKit

private struct FakeVideoHost: VideoHostRecognizing, VideoHostResolving {
    let match: VideoHostMatch?
    let result: Result<ResolvedVideo, VideoHostResolutionError>

    func recognize(_ url: URL) -> VideoHostMatch? {
        match
    }

    func resolve(_ match: VideoHostMatch) async throws -> ResolvedVideo {
        try result.get()
    }
}

struct VideoPlaybackActionTests {
    private let page = URL(string: "https://streamable.com/abc123")!
    private var match: VideoHostMatch {
        VideoHostMatch(kind: .streamable, identifier: "abc123", pageUrl: page)
    }

    @Test
    func directFileUrl_playsDirectly() async throws {
        let file = try #require(URL(string: "https://cdn.example/clip.mp4"))
        let host = FakeVideoHost(match: nil, result: .failure(.unresolvable))
        let action = await videoPlaybackAction(forVideoAt: file, using: host)
        #expect(action == .play(file))
    }

    @Test
    func recognizedAndResolved_playsStream() async throws {
        let stream = try #require(URL(string: "https://cdn.streamable.com/abc.mp4"))
        let host = FakeVideoHost(
            match: match,
            result: .success(ResolvedVideo(streamUrl: stream, posterUrl: nil, title: nil))
        )
        let action = await videoPlaybackAction(forVideoAt: page, using: host)
        #expect(action == .play(stream))
    }

    @Test
    func recognizedButResolutionFails_opensExternally() async {
        let host = FakeVideoHost(match: match, result: .failure(.notReady))
        let action = await videoPlaybackAction(forVideoAt: page, using: host)
        #expect(action == .openExternally(page))
    }
}
