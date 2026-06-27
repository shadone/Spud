//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import Spud

/// Locks the temporary-filename derivation used when sharing an animated GIF:
/// the shared file must always end in `.gif` so the share sheet treats it as an
/// animated image (sharing the decoded `UIImage` would flatten the animation).
struct MediaViewerShareTests {
    @Test
    func gifUrl_keepsItsFilename() throws {
        let url = try #require(URL(string: "https://example.test/media/cat.gif"))
        #expect(MediaViewerViewController.temporaryGIFFilename(for: url) == "cat.gif")
    }

    @Test
    func uppercaseGifExtension_isNotDoubled() throws {
        let url = try #require(URL(string: "https://example.test/media/CAT.GIF"))
        #expect(MediaViewerViewController.temporaryGIFFilename(for: url) == "CAT.GIF")
    }

    @Test
    func nonGifExtension_getsGifAppended() throws {
        let url = try #require(URL(string: "https://example.test/media/clip.mp4"))
        #expect(MediaViewerViewController.temporaryGIFFilename(for: url) == "clip.mp4.gif")
    }

    @Test
    func noExtension_getsGifAppended() throws {
        let url = try #require(URL(string: "https://example.test/media/raw"))
        #expect(MediaViewerViewController.temporaryGIFFilename(for: url) == "raw.gif")
    }

    @Test
    func rootUrl_fallsBackToImageGif() throws {
        let url = try #require(URL(string: "https://example.test"))
        #expect(MediaViewerViewController.temporaryGIFFilename(for: url) == "image.gif")
    }
}
