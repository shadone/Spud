//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudMarkdownKit

struct MediaDetectorTests {
    @Test
    func image() throws {
        #expect(try MediaDetector.kind(of: #require(URL(string: "https://x/y.jpg"))) == .image)
        #expect(try MediaDetector.kind(of: #require(URL(string: "https://x/y.PNG"))) == .image)
    }

    @Test
    func audio() throws {
        #expect(try MediaDetector.kind(of: #require(URL(string: "https://x/clip.mp3"))) == .audio)
    }

    @Test
    func video() throws {
        #expect(try MediaDetector.kind(of: #require(URL(string: "https://x/clip.mp4"))) == .video)
    }

    @Test
    func unknownDefaultsToImage() throws {
        #expect(try MediaDetector.kind(of: #require(URL(string: "https://x/pictrs/image/abc"))) == .image)
    }
}
