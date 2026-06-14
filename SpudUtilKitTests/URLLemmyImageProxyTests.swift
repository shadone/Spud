//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import XCTest
@testable import SpudUtilKit

class URLLemmyImageProxyTests: XCTestCase {
    func test_proxyUrl_returnsEmbeddedOriginal() throws {
        let url = try XCTUnwrap(URL(string: "https://lemmy.ml/api/v3/image_proxy?url=https%3A%2F%2Ffeddit.nl%2Fpictrs%2Fimage%2F5fbd8b47.png"))
        XCTAssertEqual(
            url.lemmyImageProxyOriginalUrl?.absoluteString,
            "https://feddit.nl/pictrs/image/5fbd8b47.png"
        )
    }

    func test_nonProxyUrl_returnsNil() throws {
        let url = try XCTUnwrap(URL(string: "https://feddit.nl/pictrs/image/5fbd8b47.png"))
        XCTAssertNil(url.lemmyImageProxyOriginalUrl)
    }

    func test_proxyUrlWithoutUrlQuery_returnsNil() throws {
        let url = try XCTUnwrap(URL(string: "https://lemmy.ml/api/v3/image_proxy?foo=bar"))
        XCTAssertNil(url.lemmyImageProxyOriginalUrl)
    }
}
