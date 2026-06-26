//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudUtilKit

struct URLLemmyImageProxyTests {
    @Test
    func proxyUrl_returnsEmbeddedOriginal() throws {
        let url = try #require(URL(string: "https://lemmy.ml/api/v3/image_proxy?url=https%3A%2F%2Ffeddit.nl%2Fpictrs%2Fimage%2F5fbd8b47.png"))
        #expect(
            url.lemmyImageProxyOriginalUrl?.absoluteString ==
                "https://feddit.nl/pictrs/image/5fbd8b47.png"
        )
    }

    @Test
    func nonProxyUrl_returnsNil() throws {
        let url = try #require(URL(string: "https://feddit.nl/pictrs/image/5fbd8b47.png"))
        #expect(url.lemmyImageProxyOriginalUrl == nil)
    }

    @Test
    func proxyUrlWithoutUrlQuery_returnsNil() throws {
        let url = try #require(URL(string: "https://lemmy.ml/api/v3/image_proxy?foo=bar"))
        #expect(url.lemmyImageProxyOriginalUrl == nil)
    }
}
