//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import Spud

/// Locks the temporary-filename derivation used when sharing an animated GIF:
/// the shared file must always end in `.gif` so the share sheet treats it as an
/// animated image (sharing the decoded `UIImage` would flatten the animation).
final class MediaViewerShareTests: XCTestCase {
    func test_gifUrl_keepsItsFilename() throws {
        let url = try XCTUnwrap(URL(string: "https://example.test/media/cat.gif"))
        XCTAssertEqual(MediaViewerViewController.temporaryGIFFilename(for: url), "cat.gif")
    }

    func test_uppercaseGifExtension_isNotDoubled() throws {
        let url = try XCTUnwrap(URL(string: "https://example.test/media/CAT.GIF"))
        XCTAssertEqual(MediaViewerViewController.temporaryGIFFilename(for: url), "CAT.GIF")
    }

    func test_nonGifExtension_getsGifAppended() throws {
        let url = try XCTUnwrap(URL(string: "https://example.test/media/clip.mp4"))
        XCTAssertEqual(MediaViewerViewController.temporaryGIFFilename(for: url), "clip.mp4.gif")
    }

    func test_noExtension_getsGifAppended() throws {
        let url = try XCTUnwrap(URL(string: "https://example.test/media/raw"))
        XCTAssertEqual(MediaViewerViewController.temporaryGIFFilename(for: url), "raw.gif")
    }

    func test_rootUrl_fallsBackToImageGif() throws {
        let url = try XCTUnwrap(URL(string: "https://example.test"))
        XCTAssertEqual(MediaViewerViewController.temporaryGIFFilename(for: url), "image.gif")
    }
}
