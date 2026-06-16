//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import SpudMarkdownKit

final class MediaDetectorTests: XCTestCase {
    func test_image() throws {
        XCTAssertEqual(try MediaDetector.kind(of: XCTUnwrap(URL(string: "https://x/y.jpg"))), .image)
        XCTAssertEqual(try MediaDetector.kind(of: XCTUnwrap(URL(string: "https://x/y.PNG"))), .image)
    }

    func test_audio() throws {
        XCTAssertEqual(try MediaDetector.kind(of: XCTUnwrap(URL(string: "https://x/clip.mp3"))), .audio)
    }

    func test_video() throws {
        XCTAssertEqual(try MediaDetector.kind(of: XCTUnwrap(URL(string: "https://x/clip.mp4"))), .video)
    }

    func test_unknownDefaultsToImage() throws {
        XCTAssertEqual(try MediaDetector.kind(of: XCTUnwrap(URL(string: "https://x/pictrs/image/abc"))), .image)
    }
}
